#!/bin/zsh
# Runs survey-base and survey-cand over every English corpus PDF; writes <id>.<label>.tsv.
C=/Users/trevorharmon/Development/PDFReflowLib/corpus/cache
D=/private/tmp/claude-501/i177/diag/lines
mkdir -p $D
for pair in \
  faa-phak-8083-25c:faa-h-8083-25c.pdf \
  wallace-algebra-2010:Beginning_and_Intermediate_Algebra.pdf \
  gpo-warren-1964:GPO-WARRENCOMMISSIONREPORT.pdf \
  gpo-911-2004:GPO-911REPORT.pdf \
  fed-explained-2021:the-fed-explained.pdf \
  dga-2025-2030:DGA.pdf \
  noaa-nca5-2023:noaa_61592_DS1.pdf \
  gpo-our-flag-2003:CDOC-108hdoc97.pdf \
  cia-blue-book-14-1955:CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf \
  cdc-zombie-pandemic-2011:cdc_6023_DS1.pdf \
  nbs-jres-geltman-1977:jresv82n3p173_A1b.pdf \
  arxiv-replay-clocks-2023:2311.07842v1.pdf \
  usgs-mcs2025-copper:mcs2025-copper.pdf \
  scotus-loper-bright-2024:22-451_7m58.pdf \
  census-rrs2002-01:rrs2002-01.pdf \
  uscourts-pro-se-1-2016:complaint_for_a_civil_case.pdf \
  ntrs-20200002975-gwl-2020:20200002975.pdf \
  usda-ars-agresearch-2012-11:November-December2012.pdf \
  ntrs-20190030725-dasc-2019:20190030725.pdf \
  ntrs-20180003024-earthdata-slides-2018:20180003024.pdf \
  ntrs-20210020887-techport-thm-2021:THM-Close-Out-Report-and-Exec-Summ-for-STI-Review.pdf
do
  id=${pair%%:*}; file=${pair#*:}
  for label in base cand; do
    /private/tmp/claude-501/i177/diag/survey-$label $C/$file > $D/$id.$label.tsv 2>/dev/null &
  done
  wait
  echo "$id $(wc -l < $D/$id.base.tsv) $(wc -l < $D/$id.cand.tsv)"
done
