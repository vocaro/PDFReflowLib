#!/usr/bin/env python3
"""Assess the scale, ink contrast and color of a converted image against a source-region reference.

The region correlation check proves a region is present and aligned but not that it is legible or
keeps its colors: normalized correlation ignores brightness and contrast, and grayscale references
ignore hue entirely. This module locates a reference (a 36 DPI grayscale region reference or an RGB
color reference rendered the same way) in each converted image on the page and measures:

- scale: the converted image's pixel size relative to the reviewed source region rendered at the
  library's 180 DPI. A crop emitted at lower resolution than its source region fails.
- contrast: the spread between the 2nd and 98th percentile gray values of the aligned window,
  as a fraction of full range. Washed-out or low-contrast crops fail.
- colorAgreement (color references only): the fraction of colored reference samples (chroma at
  least CHROMA_THRESHOLD) whose converted sample keeps at least half the chroma and a hue within
  HUE_TOLERANCE degrees. Grayscale or hue-shifted output fails.

Scores are measured on real corpus output in measurements/image-appearance/record.md.
"""
import io

import numpy as np
from PIL import Image

import image_regions

CHROMA_THRESHOLD = 48.0      # reference samples at least this saturated (max−min channel, 0–255) count as colored
MINIMUM_COLORED_SAMPLES = 16
HUE_TOLERANCE = 30.0         # degrees
CHROMA_RETENTION = 0.5
DEFAULT_MINIMUM_SCALE = 0.95
CONTRAST_PERCENTILES = (2, 98)
# Measured (measurements/image-appearance/record.md): correct crops score 0.52-0.66 (a pale FAA
# illustration is the lowest); crops compressed to gray levels 96-160 score 0.12-0.17.
DEFAULT_MINIMUM_CONTRAST = 0.4
DEFAULT_MINIMUM_COLOR_AGREEMENT = 0.8


def load_reference(data):
    """Return (gray, rgb-or-None) float arrays for a grayscale or RGB pooled reference."""
    image = Image.open(io.BytesIO(data))
    if image.mode == 'L':
        return np.asarray(image, dtype=np.float64), None
    if image.mode == 'RGB':
        rgb = np.asarray(image, dtype=np.float64)
        return np.asarray(image.convert('L'), dtype=np.float64), rgb
    raise ValueError('Appearance reference must be 8-bit grayscale or RGB')


def hue_and_chroma(rgb):
    """Hue in degrees (0–360) and chroma (max−min) for an H×W×3 array."""
    high, low = rgb.max(axis=2), rgb.min(axis=2)
    chroma = high - low
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    with np.errstate(divide='ignore', invalid='ignore'):
        safe = np.where(chroma > 0, chroma, 1.0)
        hue = np.where(high == r, (g - b) / safe % 6,
                       np.where(high == g, (b - r) / safe + 2, (r - g) / safe + 4)) * 60.0
    return np.where(chroma > 0, hue % 360.0, 0.0), chroma


def color_agreement(reference_rgb, window_rgb):
    reference_hue, reference_chroma = hue_and_chroma(reference_rgb)
    window_hue, window_chroma = hue_and_chroma(window_rgb)
    colored = reference_chroma >= CHROMA_THRESHOLD
    if colored.sum() < MINIMUM_COLORED_SAMPLES:
        raise ValueError('Color reference has too few colored samples')
    difference = np.abs(reference_hue - window_hue) % 360.0
    difference = np.minimum(difference, 360.0 - difference)
    agrees = (window_chroma >= CHROMA_RETENTION * reference_chroma) & (difference <= HUE_TOLERANCE)
    return float(agrees[colored].mean()), int(colored.sum())


def window(values, top, left, height, width):
    result = np.full((height, width) + values.shape[2:], 255.0)
    y0, x0 = max(top, 0), max(left, 0)
    y1, x1 = min(top + height, values.shape[0]), min(left + width, values.shape[1])
    if y1 > y0 and x1 > x0:
        result[y0 - top:y1 - top, x0 - left:x1 - left] = values[y0:y1, x0:x1]
    return result


def appearance(reference_gray, reference_rgb, region_points, image):
    """Metrics of one reference against one PIL image."""
    if image.width * image.height > image_regions.MAX_IMAGE_PIXELS:
        raise ValueError('Image exceeds the inspection pixel ceiling')
    gray = np.asarray(image.convert('L'), dtype=np.float64)
    score, phase_row, phase_column, row, column = image_regions.locate(reference_gray, gray)
    height, width = reference_gray.shape
    aligned = window(image_regions.pooled_array(gray, (phase_row, phase_column)), row, column, height, width)
    points_per_pixel = 72.0 / image_regions.RENDER_DPI
    region_width = (region_points[2] - region_points[0]) / points_per_pixel
    region_height = (region_points[3] - region_points[1]) / points_per_pixel
    low, high = np.percentile(aligned, CONTRAST_PERCENTILES)
    metrics = {
        'correlation': round(float(score), 4),
        'scale': round(float(min(image.width / region_width, image.height / region_height)), 4),
        'contrast': round(float((high - low) / 255.0), 4),
    }
    if reference_rgb is not None:
        rgb = np.asarray(image.convert('RGB'), dtype=np.float64)
        aligned_rgb = window(image_regions.pooled_array(rgb, (phase_row, phase_column)), row, column, height, width)
        agreement, colored = color_agreement(reference_rgb, aligned_rgb)
        metrics.update(colorAgreement=round(agreement, 4), coloredSamples=colored)
    return metrics


def passes(metrics, minimum_scale=DEFAULT_MINIMUM_SCALE, minimum_contrast=DEFAULT_MINIMUM_CONTRAST,
           minimum_color_agreement=DEFAULT_MINIMUM_COLOR_AGREEMENT):
    if metrics['scale'] < minimum_scale or metrics['contrast'] < minimum_contrast:
        return False
    return 'colorAgreement' not in metrics or metrics['colorAgreement'] >= minimum_color_agreement


def appearance_score(reference_data, region_points, image_datas, **thresholds):
    """(passed, metrics) across candidate converted images; metrics describe the best-correlated
    passing image, or the best-correlated image when none passes."""
    reference_gray, reference_rgb = load_reference(reference_data)
    results = []
    for data in image_datas:
        with Image.open(io.BytesIO(data)) as image:
            results.append(appearance(reference_gray, reference_rgb, region_points, image))
    if not results:
        return False, {'correlation': -1.0, 'scale': 0.0, 'contrast': 0.0}
    passing = [r for r in results if passes(r, **thresholds)]
    best = max(passing or results, key=lambda r: r['correlation'])
    return bool(passing), best
