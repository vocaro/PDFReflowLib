#!/bin/zsh
T=/private/tmp/claude-501/i158/tools
C=/Users/trevorharmon/Development/PDFReflowLib/corpus/cache
run() {
  echo -n "$1 page $2 base: "; $T/composetime-base $C/$1 $2 2>/dev/null
  echo -n "$1 page $2 cand: "; $T/composetime $C/$1 $2 2>/dev/null
}
run faa-h-8083-25c.pdf 448
run faa-h-8083-25c.pdf 226
run faa-h-8083-25c.pdf 67
run faa-h-8083-25c.pdf 288
run noaa_61592_DS1.pdf 1834
run November-December2012.pdf 2
run November-December2012.pdf 22
run THM-Close-Out-Report-and-Exec-Summ-for-STI-Review.pdf 1
run DGA.pdf 2
run CDOC-108hdoc97.pdf 48
run the-fed-explained.pdf 67
