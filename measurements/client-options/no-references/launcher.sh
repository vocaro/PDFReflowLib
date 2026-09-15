#!/bin/sh
exec "/Users/trevorharmon/Development/PDFReflowLib/.build/out/Products/Release/pdf-reflow" "$@" --reference-images never --full-page-image-encoding jpeg:0.9 --maximum-epub-bytes 67108864
