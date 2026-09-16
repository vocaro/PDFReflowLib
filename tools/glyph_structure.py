#!/usr/bin/env python3
"""Check every ink component of a full-resolution source-region reference inside a converted image.

The 36 DPI region check (image_regions.py) proves a region is present and aligned but is blind to
single glyph parts: erasing one exponent from an equation still correlates at 0.97. A glyph
reference is the same Poppler render kept at the full 180 DPI raster resolution and trimmed to its
ink with a white margin. The converted image is aligned coarsely with the 36 DPI search and refined
at full resolution; then every connected ink component of the reference (an exponent, a fraction
bar, a radical sign, a digit) must be covered by ink of comparable darkness in the converted image,
and the converted window may not carry significant ink outside the reference's dilated ink.

Coverage compares the mean 3×3-neighbourhood darkness over each component's pixels, which
tolerates one pixel of residual misalignment and different rasterizers' anti-aliasing. This proves
each stroke is present and legibly dark; it does not prove glyph identity beyond the ink shapes.
"""
import io

import numpy as np
from PIL import Image

import image_regions

RENDER_DPI = image_regions.RENDER_DPI
REFERENCE_DPI = RENDER_DPI
MARGIN = 4                 # white samples kept around the reference ink
INK_THRESHOLD = 160        # full-resolution binarization for component labelling
MIN_COMPONENT_AREA = 6     # pixels; smaller specks are anti-aliasing debris, not glyph parts
NEIGHBOURHOOD = 1          # 3×3 maximum-darkness window for the sharpness statistic
COVERAGE_DILATION = 2      # unit footprint grown by this many pixels before summing ink mass
TILE = 16                  # pixels; components are checked in tiles so a long stroke's parts count separately
EXTRA_INK_DILATION = 2     # reference ink grown by this many pixels before counting extra ink
# Measured on real crops (measurements/equation-structure/record.md): every component of a correct
# crop keeps at least 0.60 of its reference ink mass (a hairline fraction bar drawn thinner by Core
# Graphics; ordinary glyphs 1.2-1.4) with under 0.01 extra ink; erasing one exponent, fraction bar or
# radical sign leaves a component at or below 0.2; a substituted similar crop fails both measures.
DEFAULT_MINIMUM_COVERAGE = 0.4
DEFAULT_MAXIMUM_EXTRA_INK = 0.12
REFINEMENT = image_regions.POOL


def trimmed_to_ink(values, margin=MARGIN):
    """Crop a full-resolution grayscale array to its ink plus a white margin; reject blank regions."""
    ink = np.argwhere(values < image_regions.INK_THRESHOLD)
    if ink.size == 0:
        raise ValueError('Reference region contains no ink')
    (top, left), (bottom, right) = ink.min(0), ink.max(0) + 1
    cropped = values[top:bottom, left:right]
    return np.pad(cropped, margin, constant_values=255.0)


def load_reference(data):
    image = Image.open(io.BytesIO(data))
    if image.mode != 'L':
        raise ValueError('Glyph reference must be 8-bit grayscale')
    values = np.asarray(image, dtype=np.float64)
    if not (values < image_regions.INK_THRESHOLD).any():
        raise ValueError('Glyph reference contains no ink')
    return values


def components(mask, minimum_area=MIN_COMPONENT_AREA):
    """8-connected components of a boolean mask as (rows, columns) index arrays, largest first."""
    labels = np.zeros(mask.shape, dtype=np.int32)
    height, width = mask.shape
    found = []
    current = 0
    for start_y, start_x in zip(*np.nonzero(mask)):
        if labels[start_y, start_x]:
            continue
        current += 1
        labels[start_y, start_x] = current
        stack, pixels = [(int(start_y), int(start_x))], []
        while stack:
            y, x = stack.pop()
            pixels.append((y, x))
            for ny in (y - 1, y, y + 1):
                if not 0 <= ny < height:
                    continue
                for nx in (x - 1, x, x + 1):
                    if 0 <= nx < width and mask[ny, nx] and not labels[ny, nx]:
                        labels[ny, nx] = current
                        stack.append((ny, nx))
        if len(pixels) >= minimum_area:
            rows, columns = zip(*pixels)
            found.append((np.array(rows), np.array(columns)))
    found.sort(key=lambda item: -len(item[0]))
    return found


def tiles(parts, size=TILE):
    """Split each component into TILE×TILE-aligned pieces (rows, columns, component index) so long
    connected strokes (a radical with its vinculum, a fraction bar, a table rule) are checked
    piecewise. Pieces below the minimum area are skipped; a component with no piece that large is
    checked whole."""
    units = []
    for index, (rows, columns) in enumerate(parts):
        keys = (rows // size) * 1_000_000 + (columns // size)
        pieces = [(rows[keys == key], columns[keys == key], index) for key in np.unique(keys)]
        pieces = [piece for piece in pieces if len(piece[0]) >= MIN_COMPONENT_AREA]
        units.extend(pieces or [(rows, columns, index)])
    return units


def coverage_by_unit(reference, aligned, mask, parts):
    """Ink-mass ratio (converted / reference) within every unit's footprint.

    The footprint is the unit grown by COVERAGE_DILATION pixels, excluding other components' ink
    grown by one pixel and the exact pixels of the same component's other units. Blur and
    resampling spread ink but conserve it; an erased stroke leaves only its neighbours' spill.
    """
    reference_darkness, darkness = 255.0 - reference, 255.0 - aligned
    height, width = mask.shape
    labels = np.zeros(mask.shape, dtype=np.int32)
    for index, (rows, columns) in enumerate(parts):
        labels[rows, columns] = index + 1
    units = tiles(parts)
    ratios = []
    pad = COVERAGE_DILATION + 1
    for rows, columns, index in units:
        r0, r1 = max(0, int(rows.min()) - pad), min(height, int(rows.max()) + 1 + pad)
        c0, c1 = max(0, int(columns.min()) - pad), min(width, int(columns.max()) + 1 + pad)
        local = labels[r0:r1, c0:c1]
        own = np.zeros(local.shape, dtype=bool)
        own[rows - r0, columns - c0] = True
        same = (local == index + 1) & ~own
        others = (local != 0) & (local != index + 1)
        footprint = dilated(own, COVERAGE_DILATION) & ~dilated(others, 1) & ~same
        expected = reference_darkness[r0:r1, c0:c1][footprint].sum()
        ratios.append(float(darkness[r0:r1, c0:c1][footprint].sum() / expected) if expected > 0 else 0.0)
    return units, ratios


def maximum_darkness(values, radius=NEIGHBOURHOOD):
    """255 minus the minimum gray value within a (2·radius+1)² neighbourhood of every pixel."""
    padded = np.pad(values, radius, constant_values=255.0)
    darkest = np.full(values.shape, 255.0)
    for dy in range(2 * radius + 1):
        for dx in range(2 * radius + 1):
            darkest = np.minimum(darkest, padded[dy:dy + values.shape[0], dx:dx + values.shape[1]])
    return 255.0 - darkest


def dilated(mask, radius):
    grown = np.zeros_like(mask)
    padded = np.pad(mask, radius)
    for dy in range(2 * radius + 1):
        for dx in range(2 * radius + 1):
            grown |= padded[dy:dy + mask.shape[0], dx:dx + mask.shape[1]]
    return grown


def window(gray, top, left, height, width):
    """Extract a height×width window whose top-left may fall outside gray; outside is white."""
    result = np.full((height, width), 255.0)
    y0, x0 = max(top, 0), max(left, 0)
    y1, x1 = min(top + height, gray.shape[0]), min(left + width, gray.shape[1])
    if y1 > y0 and x1 > x0:
        result[y0 - top:y1 - top, x0 - left:x1 - left] = gray[y0:y1, x0:x1]
    return result


def correlation(reference, candidate):
    a, b = reference - reference.mean(), candidate - candidate.mean()
    norm = np.sqrt((a * a).sum() * (b * b).sum())
    return float((a * b).sum() / norm) if norm > 0 else -1.0


def align(reference, gray):
    """Locate the full-resolution reference in gray: (correlation, top, left, window)."""
    coarse = image_regions.pooled_array(reference)
    score, phase_row, phase_column, row, column = image_regions.locate(coarse, gray)
    if score < 0:
        return -1.0, 0, 0, window(gray, 0, 0, *reference.shape)
    top, left = row * image_regions.POOL + phase_row, column * image_regions.POOL + phase_column
    best = (-2.0, top, left)
    for dy in range(-REFINEMENT, REFINEMENT + 1):
        for dx in range(-REFINEMENT, REFINEMENT + 1):
            candidate = window(gray, top + dy, left + dx, *reference.shape)
            value = correlation(reference, candidate)
            if value > best[0]:
                best = (value, top + dy, left + dx)
    return best[0], best[1], best[2], window(gray, best[1], best[2], *reference.shape)


def structure(reference, gray):
    """Metrics of a full-resolution reference against one grayscale image array."""
    ncc, top, left, aligned = align(reference, gray)
    mask = reference < INK_THRESHOLD
    parts = components(mask)
    if not parts:
        raise ValueError('Glyph reference has no ink component of the minimum area')
    darkness = 255.0 - aligned
    units, coverage = coverage_by_unit(reference, aligned, mask, parts)
    weakest = int(np.argmin(coverage))
    rows, columns, _ = units[weakest]
    outside = darkness[~dilated(mask, EXTRA_INK_DILATION)].sum()
    total = darkness.sum()
    # Sharpness: peak darkness reached beside each stroke relative to the reference. Reported for
    # review and gated only when a contract asks: measured values do not separate a mild blur from
    # an illegible upsample (see the evidence record).
    reference_peak, candidate_peak = maximum_darkness(reference), maximum_darkness(aligned)
    peaks = [float(candidate_peak[r, c].mean() / reference_peak[r, c].mean()) for r, c in parts]
    return {
        'correlation': round(ncc, 4), 'top': top, 'left': left, 'components': len(parts),
        'coverage': round(min(coverage), 4),
        'weakestComponent': [int(columns.min()), int(rows.min()), int(columns.max()) + 1, int(rows.max()) + 1],
        'extraInk': round(float(outside / total), 4) if total > 0 else 0.0,
        'sharpness': round(float(np.median(peaks)), 4), 'weakestStroke': round(min(peaks), 4),
    }


def passes(metrics, minimum_coverage=DEFAULT_MINIMUM_COVERAGE, maximum_extra_ink=DEFAULT_MAXIMUM_EXTRA_INK,
           minimum_sharpness=None):
    return (metrics['coverage'] >= minimum_coverage and metrics['extraInk'] <= maximum_extra_ink
            and (minimum_sharpness is None or metrics['sharpness'] >= minimum_sharpness))


def structure_score(reference_data, image_datas, minimum_coverage=DEFAULT_MINIMUM_COVERAGE,
                    maximum_extra_ink=DEFAULT_MAXIMUM_EXTRA_INK, minimum_sharpness=None):
    """Best structure metrics of one reference across candidate converted images (encoded bytes).

    Returns (passed, metrics): passed when any image satisfies every threshold; metrics describe the
    best candidate (highest coverage among passing images, else highest coverage).
    """
    reference = load_reference(reference_data)
    results = []
    for data in image_datas:
        with Image.open(io.BytesIO(data)) as image:
            gray = image.convert('L')
            if gray.width * gray.height > image_regions.MAX_IMAGE_PIXELS:
                raise ValueError('Image exceeds the inspection pixel ceiling')
            results.append(structure(reference, np.asarray(gray, dtype=np.float64)))
    if not results:
        return False, {'correlation': -1.0, 'coverage': 0.0, 'extraInk': 1.0, 'components': 0, 'sharpness': 0.0}
    passing = [r for r in results if passes(r, minimum_coverage, maximum_extra_ink, minimum_sharpness)]
    best = max(passing or results, key=lambda r: (r['coverage'], -r['extraInk']))
    return bool(passing), best
