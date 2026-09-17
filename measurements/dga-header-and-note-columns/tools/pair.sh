#!/bin/bash
# usage: pair.sh pdfname [extra converter args]  -- converts with base and cand (--ocr never, pinned), compares bytes
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/i141
C=/Users/trevorharmon/Development/PDFReflowLib/corpus/cache
name="$1"; shift
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if (( free < 5 )); then echo "STOP: under 5 GB free"; exit 3; fi
mkdir -p $S/pairs
start=$(date +%s)
$S/base/pdf-reflow $C/$name $S/pairs/$name.base.epub --ocr never --package-identifier x --modification-date 2026-01-01T00:00:00Z "$@" > $S/pairs/$name.base.json 2>&1 &
$S/cand/pdf-reflow $C/$name $S/pairs/$name.cand.epub --ocr never --package-identifier x --modification-date 2026-01-01T00:00:00Z "$@" > $S/pairs/$name.cand.json 2>&1
wait
end=$(date +%s)
if cmp -s $S/pairs/$name.base.epub $S/pairs/$name.cand.epub; then
  echo "$name identical ($((end-start))s)"
  rm -f $S/pairs/$name.base.epub $S/pairs/$name.cand.epub
else
  echo "$name DIFFERENT ($((end-start))s)"
  python3 $S/tools/epubdiff.py $S/pairs/$name.base.epub $S/pairs/$name.cand.epub
fi
