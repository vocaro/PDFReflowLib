#!/bin/zsh
# Recognize every page of the corpus's scanned books with survey-ocr (built beforehand).
# usage: survey-ocr-all.sh <survey-ocr executable> <output dir> [book ...]
tool=$1; out=$2; shift 2
cache=${0:A:h}/../../corpus/cache
mkdir -p $out
typeset -A pdfs
pdfs=(cdc cdc_6023_DS1.pdf bluebook CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf
      warren GPO-WARRENCOMMISSIONREPORT.pdf nbs jresv82n3p173_A1b.pdf census rrs2002-01.pdf)
books=($@)
[ ${#books} -eq 0 ] && books=(cdc nbs census bluebook warren)
for book in $books; do
  start=$SECONDS
  $tool $cache/$pdfs[$book] > $out/$book-ocr.jsonl 2> $out/$book-ocr.err
  echo "$book $(wc -l < $out/$book-ocr.jsonl) pages, $((SECONDS - start)) s"
done
