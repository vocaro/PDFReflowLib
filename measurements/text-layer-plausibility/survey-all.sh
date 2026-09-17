#!/bin/zsh
# Build survey-pages from the library's current sources and survey every English corpus book
# (seventeen; the Arabic and Chinese cases are not judged).
# usage: survey-all.sh <output dir> [book ...]
out=$1; shift
root=${0:A:h}/../..
cache=$root/corpus/cache
mkdir -p $out
sources=(${(f)"$(ls $root/Sources/PDFReflowLib/*.swift | grep -v -e EPUBWriter.swift -e PDFConverter.swift)"})
xcrun swiftc -parse-as-library -enable-bare-slash-regex -swift-version 6 -O $sources $root/measurements/text-layer-plausibility/survey-pages.swift \
  -o $out/survey-pages 2> $out/build.log || { tail -20 $out/build.log; exit 1 }
typeset -A pdfs
pdfs=(cdc cdc_6023_DS1.pdf bluebook CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf
      warren GPO-WARRENCOMMISSIONREPORT.pdf nbs jresv82n3p173_A1b.pdf census rrs2002-01.pdf
      dga DGA.pdf faa faa-h-8083-25c.pdf algebra Beginning_and_Intermediate_Algebra.pdf
      911 GPO-911REPORT.pdf flag CDOC-108hdoc97.pdf fed the-fed-explained.pdf loper 22-451_7m58.pdf
      replay 2311.07842v1.pdf usgs mcs2025-copper.pdf noaa noaa_61592_DS1.pdf
      prose1 complaint_for_a_civil_case.pdf nasa 20200002975.pdf)
books=($@)
[ ${#books} -eq 0 ] && books=(cdc bluebook warren nbs census dga faa algebra 911 flag fed loper replay usgs noaa prose1 nasa)
for book in $books; do
  start=$SECONDS
  $out/survey-pages $cache/$pdfs[$book] > $out/$book.jsonl 2> $out/$book.err
  echo "$book $(wc -l < $out/$book.jsonl) image-backed pages, $((SECONDS - start)) s"
done
