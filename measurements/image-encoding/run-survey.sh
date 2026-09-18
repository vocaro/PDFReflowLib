#!/bin/sh
# Drive survey.py over the English corpus, one case at a time, checking free space before each
# and deleting every output as soon as its numbers are recorded. NOAA and Warren are not here:
# they are run singly, last, by name.
#
# Needs a release converter and the ImageIO re-encoder:
#   swift build -c release
#   xcrun swiftc -O measurements/image-encoding/reencode.swift -o "$SCRATCH/reencode"
set -e
root=$(cd "$(dirname "$0")/../.." && pwd)
scratch=${SCRATCH:-/private/tmp/claude-501/ienc}
rows="$scratch/rows"
summary="$scratch/summary"
reencode="$scratch/reencode"
converter="$root/.build/release/pdf-reflow"
crops="$root/measurements/image-encoding/crops"

# Documents whose rights forbid committing any raster or crop (doc/corpus.md): the two NASA
# insignia decks, the two NASA papers, the ARS magazine and the Pro Se form. They are measured
# like every other book; only their crops are withheld.
no_crops="ntrs-20180003024-earthdata-slides-2018 ntrs-20210020887-techport-thm-2021 ntrs-20190030725-dasc-2019 ntrs-20200002975-gwl-2020 usda-ars-agresearch-2012-11 uscourts-pro-se-1-2016"

run() {
  case_id=$1; pdf=$2; shift 2
  free=$(df -g /System/Volumes/Data | awk 'NR==2 {print $4}')
  if [ "$free" -lt 8 ]; then echo "only ${free} GiB free; stopping before $case_id"; exit 1; fi
  echo "--- $case_id (${free} GiB free)"
  crop_option=""
  case " $no_crops " in *" $case_id "*) crop_option="" ;; *) crop_option="--crops $crops" ;; esac
  # shellcheck disable=SC2086
  python3 "$root/measurements/image-encoding/survey.py" --case "$case_id" \
    --pdf "$root/corpus/cache/$pdf" --converter "$converter" --reencode "$reencode" \
    --scratch "$scratch/work" --rows "$rows/$case_id.jsonl" --summary "$summary/$case_id.json" \
    $crop_option "$@"
}

case "${1:-all}" in
all)
  run usgs-mcs2025-copper mcs2025-copper.pdf
  run uscourts-pro-se-1-2016 complaint_for_a_civil_case.pdf
  run ntrs-20190030725-dasc-2019 20190030725.pdf
  run ntrs-20210020887-techport-thm-2021 THM-Close-Out-Report-and-Exec-Summ-for-STI-Review.pdf
  run ntrs-20180003024-earthdata-slides-2018 20180003024.pdf
  run arxiv-replay-clocks-2023 2311.07842v1.pdf
  run ntrs-20200002975-gwl-2020 20200002975.pdf
  run dga-2025-2030 DGA.pdf
  run census-rrs2002-01 rrs2002-01.pdf
  run nbs-jres-geltman-1977 jresv82n3p173_A1b.pdf
  run gpo-our-flag-2003 CDOC-108hdoc97.pdf
  run gpo-911-2004 GPO-911REPORT.pdf
  run fed-explained-2021 the-fed-explained.pdf
  run usda-ars-agresearch-2012-11 November-December2012.pdf
  run wallace-algebra-2010 Beginning_and_Intermediate_Algebra.pdf
  run cdc-zombie-pandemic-2011 cdc_6023_DS1.pdf
  run cia-blue-book-14-1955 CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf
  run faa-phak-8083-25c faa-h-8083-25c.pdf
  ;;
noaa) run noaa-nca5-2023 noaa_61592_DS1.pdf ;;
warren) run gpo-warren-1964 GPO-WARRENCOMMISSIONREPORT.pdf ;;
*) echo "usage: run-survey.sh [all|noaa|warren]"; exit 2 ;;
esac
