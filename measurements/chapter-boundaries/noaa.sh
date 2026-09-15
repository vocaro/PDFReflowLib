#!/bin/sh
# The same explicit storage policy as the retained full NOAA PNG baseline.
chapter_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec "$chapter_root/.build/release/pdf-reflow" "$@" --full-page-image-encoding png --maximum-output-bytes 4294967296 --maximum-epub-bytes 4294967296
