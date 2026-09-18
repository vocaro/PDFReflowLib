#!/bin/zsh
# usage: entryrun.sh <binary> <outdir>
B=$1; O=$2
mkdir -p $O
for f in faa-h-8083-25c.pdf Beginning_and_Intermediate_Algebra.pdf GPO-911REPORT.pdf the-fed-explained.pdf DGA.pdf noaa_61592_DS1.pdf CDOC-108hdoc97.pdf cdc_6023_DS1.pdf jresv82n3p173_A1b.pdf 2311.07842v1.pdf mcs2025-copper.pdf 22-451_7m58.pdf rrs2002-01.pdf complaint_for_a_civil_case.pdf 20200002975.pdf November-December2012.pdf 20190030725.pdf 20180003024.pdf THM-Close-Out-Report-and-Exec-Summ-for-STI-Review.pdf CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf GPO-WARRENCOMMISSIONREPORT.pdf; do
  $B /Users/trevorharmon/Development/PDFReflowLib/corpus/cache/$f > $O/$f.txt 2>/dev/null
  echo "$f $(tail -1 $O/$f.txt)"
done
