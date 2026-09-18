#!/usr/bin/env python3
"""Prototype content classifier for the images a conversion emits, and the features it reads.

Two halves, deliberately separated:

* `features(rgb)` reads only the raster. Everything it computes is available to
  `PageRasterizer` before the image is encoded, from the `CGImage` it already holds.
* `classify(features, evidence)` is the rule. `evidence` is the page-level PDF-side
  information the library already has or can cheaply obtain: whether the page carries native
  text, and what the page's image XObjects are (how many, how large, and what filter they use).

This is a measurement prototype, not library code. It is written in Python because the survey
that grades it is, and because the rule is meant to be argued about before it is ported.
"""
import numpy as np

# Classes. The first four are encoding-relevant in their own right; `mixed` is the residue.
PHOTOGRAPH = "photograph"
CONTINUOUS_TONE = "continuous-tone art"
LINE_ART = "line art or chart"
# Scanned pages split by what the scan is made of, because that, not the subject, decides
# whether PNG can compress it: a bilevel fax scan is a two-colour image PNG packs tightly, a
# tonal scan of tinted paper is a photograph of a page and PNG cannot pack it at all.
TEXT_SCAN_BILEVEL = "text page (bilevel scan)"
TEXT_SCAN_TONAL = "text page (tonal scan)"
TEXT_DIGITAL = "text page (born-digital)"
MIXED = "mixed"
CLASSES = (PHOTOGRAPH, CONTINUOUS_TONE, LINE_ART, TEXT_SCAN_BILEVEL, TEXT_SCAN_TONAL,
           TEXT_DIGITAL, MIXED)
TEXT_CLASSES = (TEXT_SCAN_BILEVEL, TEXT_SCAN_TONAL, TEXT_DIGITAL)

# JPEG is safe on these; the rest carry sharp edges that ring.
TONAL_CLASSES = (PHOTOGRAPH, CONTINUOUS_TONE)


def _gradient(gray):
    """Maximum absolute neighbour difference per pixel, same shape as `gray`."""
    dx = np.zeros_like(gray)
    dy = np.zeros_like(gray)
    dx[:, :-1] = np.abs(gray[:, 1:] - gray[:, :-1])
    dy[:-1, :] = np.abs(gray[1:, :] - gray[:-1, :])
    grad = np.maximum(dx, dy)
    grad[:, 1:] = np.maximum(grad[:, 1:], dx[:, :-1])
    grad[1:, :] = np.maximum(grad[1:, :], dy[:-1, :])
    return grad


def features(rgb):
    """Raster-only features. `rgb` is uint8 (h, w, 3)."""
    height, width = rgb.shape[:2]
    count = height * width
    gray = (0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]).astype(np.float32)
    grad = _gradient(gray)

    packed = (rgb[..., 0].astype(np.uint32) << 16 | rgb[..., 1].astype(np.uint32) << 8
              | rgb[..., 2].astype(np.uint32))
    colours, counts = np.unique(packed, return_counts=True)
    spread = rgb.max(axis=2).astype(np.int16) - rgb.min(axis=2).astype(np.int16)

    # The ground the image sits on: the modal colour, and everything within 10 levels of it in
    # every channel. A page of type is mostly its paper, whether the paper is white, grey or
    # yellowed; `whiteShare` alone misses every scan that is not white.
    modal = int(colours[int(counts.argmax())])
    ground = np.array([(modal >> 16) & 255, (modal >> 8) & 255, modal & 255], dtype=np.int16)
    signed = rgb.astype(np.int16)
    background = float((np.abs(signed - ground).max(axis=2) <= 10).mean())

    # Colour, measured against the page's own ground rather than against grey. Yellowed paper
    # has a channel spread of 25 to 40 levels in every pixel, so an absolute spread test calls a
    # whole scanned book "coloured"; what matters is how many pixels have a *different* hue from
    # the paper they sit on.
    chroma = np.stack([signed[..., 0] - signed[..., 1], signed[..., 1] - signed[..., 2]], axis=-1)
    ground_chroma = np.array([ground[0] - ground[1], ground[1] - ground[2]], dtype=np.int16)
    chroma_share = float((np.abs(chroma - ground_chroma).max(axis=-1) >= 24).mean())

    # How much of the image is darker than its ground: the ink, roughly. And how much of it is
    # only ever ground or ink, with nothing in between — the thing PNG packs and JPEG cannot.
    ground_gray = 0.299 * ground[0] + 0.587 * ground[1] + 0.114 * ground[2]
    ink = float((gray < ground_gray - 40).mean())
    bilevel = float((np.abs(signed - ground).max(axis=2) <= 32).mean()
                    + (gray < ground_gray - 110).mean())

    hard = float((grad >= 64).mean())
    soft = float(((grad >= 6) & (grad < 64)).mean())
    return {
        "backgroundShare": background,
        "backgroundColour": [int(v) for v in ground],
        "chromaShare": chroma_share,
        "inkShare": ink,
        "bilevelShare": min(1.0, bilevel),
        "pixels": int(count),
        "width": int(width),
        "height": int(height),
        "distinctColours": int(colours.size),
        "distinctRate": float(colours.size) / count,
        "topColourShare": float(counts.max()) / count,
        # Flat: no neighbour differs at all. Line art and charts sit on flat fields; a
        # photograph's sensor noise leaves almost no pixel with a zero gradient.
        "flatShare": float((grad == 0).mean()),
        "whiteShare": float((rgb.min(axis=2) >= 247).mean()),
        "darkShare": float((gray <= 64).mean()),
        "hardEdgeShare": hard,
        "softEdgeShare": soft,
        # Of the pixels that carry any edge at all, how many are step edges rather than ramps.
        "hardRatio": float(hard / (hard + soft)) if (hard + soft) > 0 else 0.0,
        "colourShare": float((spread >= 24).mean()),
        "meanGradient": float(grad.mean()),
    }


def classify(f, evidence=None):
    """Return (class, reason). `evidence` may be None: the rule then reads the raster alone.

    `text page` is a whole-page class. A region crop that is nothing but type — a cropped table,
    an equation — is reported as line art, because it is drawn matter and takes the same
    encoding; only a full-page reference can be a text page.
    """
    evidence = evidence or {}
    kind = evidence.get("kind", "reference")
    has_text = bool(evidence.get("pageHasText"))
    filters = set(evidence.get("pageImageFilters") or ())
    # A page whose type arrives inside an image XObject is a scan; one with no image behind it
    # draws its type itself. In the library this is the image-backed-page signal the extractor
    # already computes, not a filter list.
    scanned = bool(filters)

    flat, hard, soft = f["flatShare"], f["hardEdgeShare"], f["softEdgeShare"]
    ratio, colour = f["hardRatio"], f.get("chromaShare", f["colourShare"])
    ground = f["backgroundShare"]
    # Two-tone enough that a lossless coder has almost nothing to carry.
    drawn = f.get("bilevelShare", 0.0) >= 0.95 and f["distinctColours"] <= 4096

    # 1. Mostly one ground colour, one hue, carrying step edges and almost no ramps: type.
    typeset = ground >= 0.20 and colour < 0.10 and soft < 0.15 and ratio >= 0.40 and hard >= 0.01
    if typeset:
        if kind != "reference":
            return LINE_ART, "type on a flat ground, cropped from a page"
        if scanned or not has_text:
            return ((TEXT_SCAN_BILEVEL if drawn else TEXT_SCAN_TONAL),
                    "page of type, drawn from an image")
        return TEXT_DIGITAL, "page of type on a flat ground, drawn as text"

    # 2. Few enough colours, on a flat enough ground, to be drawn rather than captured.
    if f["distinctColours"] <= 4096 and flat >= 0.30:
        return LINE_ART, "few colours on flat fields"

    # 3. Captured tone: almost nothing flat, ramps everywhere, no ground to speak of.
    if flat <= 0.12 and soft >= 0.30 and ground <= 0.15:
        return PHOTOGRAPH, "unflat, ramp-dominated, no ground"
    if (filters & {"jpeg", "jpx"}) and flat <= 0.25 and soft >= 0.25 and ground <= 0.30:
        return PHOTOGRAPH, "ramp-dominated over a JPEG XObject"

    # 4. Drawn tone: gradients and washes, but flat fields and hard outlines survive.
    if soft >= 0.20 and ground <= 0.55 and flat <= 0.55:
        return CONTINUOUS_TONE, "washes and gradients over flat fields"

    # 5. Drawn: hard edges dominate what edge there is, on a flat ground.
    if ratio >= 0.40 and flat >= 0.45:
        return LINE_ART, "step edges on a flat ground"

    return MIXED, "neither type on paper nor captured tone"


def lossy_is_safe(klass, f, kind="reference"):
    """Whether JPEG at 0.85 to 0.95 can be used here without a visible defect.

    Measured over 6,076 corpus images: at every quality in that range ImageIO halves the chroma
    planes, so the damage that shows is chroma damage on hard coloured edges. An image with no
    chroma to lose (`chromaShare` under 0.02) is undamaged whatever it depicts — 20 of 4,286
    reached a worst 8x8 edge-block error of 30 levels, against 20 to 26 per cent above that
    threshold — and tonal content hides the subsampling in its own gradients.

    A full-page reference is a picture of a page the reader already has reflowed beside it; a
    region crop is often the only copy of a figure, and the figures that ring are exactly the
    cropped diagrams with saturated labels. So `mixed` is admitted for pages and refused for
    crops.
    """
    if f.get("chromaShare", 1.0) < 0.02:
        return True
    if klass in TONAL_CLASSES or klass == TEXT_SCAN_TONAL:
        return True
    return kind == "reference" and klass == MIXED


def encode_as_jpeg(klass, f, kind="reference", png_bytes=None, jpeg_bytes=None):
    """The proposed default: lossy where lossy is safe, and only where it is also smaller.

    The classifier answers whether lossy may be used; `smallest` answers whether it is worth
    using. Neither question answers the other: JPEG is larger than PNG on 4,079 line-art crops
    and smaller on the scans, and `smallest` alone cannot see a ringing label.
    """
    if not lossy_is_safe(klass, f, kind):
        return False
    if png_bytes is None or jpeg_bytes is None:
        return True
    return jpeg_bytes < png_bytes
