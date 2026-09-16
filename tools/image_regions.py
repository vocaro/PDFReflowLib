#!/usr/bin/env python3
"""Locate a reviewed source-region reference inside a converted EPUB image.

References are grayscale renders of a source region at REFERENCE_DPI, averaged down from
RENDER_DPI and trimmed to their ink. Converted images are assumed to use the library's default
180 DPI raster resolution and are averaged by the same factor. Normalized cross-correlation over
every placement finds the best match; a white margin tolerates crops that end exactly at the ink.
Averaging is repeated at every grid phase of the converted image. This proves the region's
content is present and aligned, not that fine detail is legible.
"""
import io

import numpy as np
from PIL import Image

RENDER_DPI = 180
REFERENCE_DPI = 36
POOL = RENDER_DPI // REFERENCE_DPI
INK_THRESHOLD = 200
EDGE_TOLERANCE = 2
# Measured with grid-phase search: correct corpus crops score 0.982-0.997 and a 1.5-pixel blur 0.959;
# wrong or half-blanked images score at most 0.64 and half-substituted synthetic rows 0.915.
DEFAULT_MINIMUM_CORRELATION = 0.95
# Converted pages are bounded by the raster pixel ceiling; references are much smaller.
MAX_IMAGE_PIXELS = 48_000_000


def pooled_array(values, offset=(0, 0)):
    """Average an H×W or H×W×C float array over POOL×POOL blocks from (row, column) offset."""
    values = values[offset[0]:, offset[1]:]
    height, width = values.shape[0] // POOL * POOL, values.shape[1] // POOL * POOL
    if height == 0 or width == 0:
        return np.full((0, 0) + values.shape[2:], 255.0)
    blocks = values[:height, :width].reshape((height // POOL, POOL, width // POOL, POOL) + values.shape[2:])
    return blocks.mean(axis=(1, 3))


def pooled(image, offset=(0, 0)):
    """Average a grayscale image over POOL×POOL blocks starting at (row, column) offset."""
    gray = image.convert('L') if image.mode != 'L' else image
    if gray.width * gray.height > MAX_IMAGE_PIXELS:
        raise ValueError('Image exceeds the inspection pixel ceiling')
    return pooled_array(np.asarray(gray, dtype=np.float64), offset)


def trimmed_to_ink(values):
    """Crop to the ink bounding box plus a one-sample margin; reject regions without ink."""
    ink = np.argwhere(values < INK_THRESHOLD)
    if ink.size == 0:
        raise ValueError('Reference region contains no ink')
    (top, left), (bottom, right) = ink.min(0), ink.max(0) + 1
    return values[max(0, top - 1):bottom + 1, max(0, left - 1):right + 1]


def _window_sums(values, height, width):
    integral = np.pad(values, ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    return (integral[height:, width:] - integral[:-height, width:]
            - integral[height:, :-width] + integral[:-height, :-width])


def best_placement(reference, image):
    """(score, row, column) of the best normalized cross-correlation placement of reference in image.

    The row/column locate the reference's top-left in image coordinates; they can be negative by
    up to EDGE_TOLERANCE because the image is padded with white on every side.
    """
    template = np.asarray(reference, dtype=np.float64)
    target = np.pad(np.asarray(image, dtype=np.float64), EDGE_TOLERANCE, constant_values=255.0)
    height, width = template.shape
    if height == 0 or width == 0 or height > target.shape[0] or width > target.shape[1]:
        return -1.0, 0, 0
    centered = template - template.mean()
    template_norm = np.sqrt((centered * centered).sum())
    if template_norm == 0:
        return -1.0, 0, 0
    count = height * width
    sums = _window_sums(target, height, width)
    squares = _window_sums(target * target, height, width)
    variance = np.maximum(squares - sums * sums / count, 0.0)
    spectrum = np.fft.rfft2(target) * np.conj(np.fft.rfft2(centered, s=target.shape))
    products = np.fft.irfft2(spectrum, s=target.shape)[:sums.shape[0], :sums.shape[1]]
    with np.errstate(divide='ignore', invalid='ignore'):
        scores = np.where(variance > 1e-9, products / (template_norm * np.sqrt(variance)), -1.0)
    row, column = np.unravel_index(int(scores.argmax()), scores.shape)
    return float(np.clip(scores.max(), -1.0, 1.0)), int(row) - EDGE_TOLERANCE, int(column) - EDGE_TOLERANCE


def best_correlation(reference, image):
    """Highest normalized cross-correlation of reference over every placement in image."""
    return best_placement(reference, image)[0]


def locate(reference, gray):
    """Best (score, phase_row, phase_column, row, column) of a pooled reference in a full-resolution
    grayscale array; row/column are the reference's top-left in pooled coordinates of that phase."""
    best = (-1.0, 0, 0, 0, 0)
    for row in range(POOL):
        for column in range(POOL):
            score, y, x = best_placement(reference, pooled_array(gray, (row, column)))
            if score > best[0]:
                best = (score, row, column, y, x)
    return best


def load_reference(data):
    image = Image.open(io.BytesIO(data))
    if image.mode != 'L':
        raise ValueError('Region reference must be 8-bit grayscale')
    return np.asarray(image, dtype=np.float64)


def region_score(reference_data, image_datas):
    """Best score of one reference across candidate converted images (encoded bytes)."""
    reference = load_reference(reference_data)
    best = -1.0
    for data in image_datas:
        with Image.open(io.BytesIO(data)) as image:
            gray = image.convert('L')
            if gray.width * gray.height > MAX_IMAGE_PIXELS:
                raise ValueError('Image exceeds the inspection pixel ceiling')
            # A crop's origin is arbitrary relative to the reference's averaging grid. Averaging
            # at every grid phase removes up to four pixels of sampling misalignment.
            best = max(best, locate(reference, np.asarray(gray, dtype=np.float64))[0])
    return best
