#!/bin/bash
# usage: census.sh <label: base|cand|gs> <book> : census/<book>-<label>.tsv and .repairs.tsv; lines kept in the scratchpad
T=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$T/../../.." && pwd)
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/spacing-maps
case $2 in
  faa) pdf=faa-h-8083-25c.pdf ;; dga) pdf=DGA.pdf ;; fed) pdf=the-fed-explained.pdf ;; our-flag) pdf=CDOC-108hdoc97.pdf ;;
  911) pdf=GPO-911REPORT.pdf ;; wallace) pdf=Beginning_and_Intermediate_Algebra.pdf ;; loper) pdf=22-451_7m58.pdf ;;
  usgs) pdf=mcs2025-copper.pdf ;; replay) pdf=2311.07842v1.pdf ;;
  *) echo "unknown book"; exit 2 ;;
esac
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
mkdir -p "$T/../census" "$S/lines"
start=$(date +%s)
"$S/bin/census-$1" "$W/corpus/cache/$pdf" "$S/lines/$2-$1.tsv" "$T/../census/$2-$1.repairs.tsv" >"$T/../census/$2-$1.tsv" 2> "$S/lines/$2-$1.stderr"
echo "rc=$? free=${free}G secs=$(( $(date +%s) - start ))"
head -3 "$S/lines/$2-$1.stderr"
python3 - "$T/../census/$2-$1.tsv" <<'EOF'
import csv, sys, collections
rows = list(csv.DictReader(open(sys.argv[1]), delimiter='\t'))
pages = len(rows)
rejected = [r for r in rows if int(r['strictRejected']) > 0]
onebyte = [r for r in rows if int(r['oneByteAccepted']) > 0]
other = [r for r in rows if r['otherRejected'] != '-']
reasons = collections.Counter()
for r in other:
    for part in r['otherRejected'].split(','):
        k, v = part.rsplit('=', 1); reasons[k] += int(v)
fonts = sum(int(r['simpleFonts']) for r in rows); fr = sum(int(r['strictRejected']) for r in rows); fo = sum(int(r['oneByteAccepted']) for r in rows)
print(f"pages with measured simple fonts {pages} (styled {sum(r['styled']=='true' for r in rows)}); pages with a rejected map {len(rejected)}; "
      f"pages with an Adobe one-byte map {len(onebyte)}; pages with other rejections {len(other)}")
print(f"font-page uses {fonts}; strict-rejected {fr}; one-byte-accepted {fo}; other {dict(reasons)}")
print(f"shows {sum(int(r['shows']) for r in rows)}; decoded {sum(int(r['decoded']) for r in rows)}; measured {sum(int(r['measured']) for r in rows)}; "
      f"pages with decoded shows {sum(int(r['decoded'])>0 for r in rows)}; pages with no evidence {sum(int(r['shows'])==0 for r in rows)}")
EOF
