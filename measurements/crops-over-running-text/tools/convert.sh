#!/bin/zsh
# usage: convert.sh <base|cand> <pdfname> <label> [extra args...]
set -e
S=/private/tmp/claude-501/i158
C=/Users/trevorharmon/Development/PDFReflowLib/corpus/cache
side=$1; pdf=$2; label=$3; shift 3
mkdir -p $S/out/$side
$S/$side/bin/pdf-reflow $C/$pdf $S/out/$side/$label.epub --ocr never \
  --package-identifier urn:uuid:00000000-0000-4000-8000-000000000000 \
  --modification-date 2026-01-01T00:00:00Z "$@" > $S/out/$side/$label.log 2>&1
echo "$side/$label exit $? $(ls -la $S/out/$side/$label.epub | awk '{print $5}') bytes"
