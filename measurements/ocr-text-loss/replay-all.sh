#!/bin/zsh
# Rebuild replay-coverage from the library's current OCRTextCoverage and replay every recorded book.
# usage: replay-all.sh <scratch dir with runs/> <corpus cache dir> [probe name, default tl116ref] [output dir]
# Environment REPLAY_MIN_GLYPHS is passed through to the replay.
scratch=$1; cache=$2; name=${3:-tl116ref}; out=${4:-$1}; mkdir -p $out
root=${0:A:h}/../..
xcrun swiftc -parse-as-library -O $root/Sources/PDFReflowLib/OCRTextCoverage.swift \
  $root/Sources/PDFReflowLib/PageRasterizer.swift $root/Sources/PDFReflowLib/ConversionTypes.swift \
  $root/Sources/PDFReflowLib/DocumentModel.swift $root/Sources/PDFReflowLib/ReflowDocument.swift \
  $root/measurements/ocr-text-loss/replay-coverage.swift -o $scratch/replay || exit 1
typeset -A pdfs
pdfs=(census rrs2002-01.pdf cdc cdc_6023_DS1.pdf warren GPO-WARRENCOMMISSIONREPORT.pdf
      warren-sample GPO-WARRENCOMMISSIONREPORT.pdf jres jresv82n3p173_A1b.pdf flag CDOC-108hdoc97.pdf
      bluebook CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf)
for book in census cdc warren warren-sample jres flag bluebook; do
  [ -f $scratch/runs/$name-$book.jsonl ] || continue
  $scratch/replay $cache/$pdfs[$book] $scratch/runs/$name-$book.jsonl > $out/replay-$book.jsonl 2>/dev/null
done
