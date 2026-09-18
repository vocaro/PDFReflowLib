#!/bin/zsh
# usage: survey.sh <binary> <outdir> [doc ...]
B=$1; O=$2; shift 2
C=/Users/trevorharmon/Development/PDFReflowLib/corpus/cache
mkdir -p $O
typeset -A files
files=(faa faa-h-8083-25c.pdf wallace Beginning_and_Intermediate_Algebra.pdf warren GPO-WARRENCOMMISSIONREPORT.pdf
  911 GPO-911REPORT.pdf fed the-fed-explained.pdf dga DGA.pdf noaa noaa_61592_DS1.pdf flag CDOC-108hdoc97.pdf
  bluebook CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf cdc cdc_6023_DS1.pdf nbs jresv82n3p173_A1b.pdf
  arxiv 2311.07842v1.pdf usgs mcs2025-copper.pdf loper 22-451_7m58.pdf census rrs2002-01.pdf courts complaint_for_a_civil_case.pdf
  gwl 20200002975.pdf mag November-December2012.pdf dasc 20190030725.pdf slides 20180003024.pdf thm THM-Close-Out-Report-and-Exec-Summ-for-STI-Review.pdf)
docs=("$@")
if (( ${#docs} == 0 )); then docs=(dga usgs nbs arxiv census courts gwl mag dasc slides thm flag cdc fed loper wallace 911 faa bluebook warren noaa); fi
for d in $docs; do
  s=$(date +%s)
  $B $C/${files[$d]} > $O/$d.txt 2>/dev/null
  echo "$d $(( $(date +%s) - s ))s $(grep -c '^[0-9]' $O/$d.txt) pages"
done
