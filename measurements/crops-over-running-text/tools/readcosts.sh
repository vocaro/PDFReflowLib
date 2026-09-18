#!/bin/zsh
T=/private/tmp/claude-501/i158/tools
C=/Users/trevorharmon/Development/PDFReflowLib/corpus/cache
run() {
  echo -n "$1 page $2 base: "; $T/readtime-base $C/$1 $2 2>/dev/null
  echo -n "$1 page $2 cand: "; $T/readtime $C/$1 $2 2>/dev/null
}
run faa-h-8083-25c.pdf 448
run faa-h-8083-25c.pdf 226
run faa-h-8083-25c.pdf 67
run noaa_61592_DS1.pdf 1834
run November-December2012.pdf 2
run the-fed-explained.pdf 67
run CDOC-108hdoc97.pdf 48
