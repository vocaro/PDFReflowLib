#!/bin/bash
# usage: one.sh <binary-label: base|cand> <pdf-basename> <out-label>
# Pinned conversion -> w/<label>.txt (blocks, block-dump.py), .nav/.img (nav.py), .json (report), .sha; EPUB deleted.
T=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$T/../../.." && pwd)
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue91
bin="$S/bin/$1"; pdf="$2"; [ "${pdf#/}" = "$pdf" ] && pdf="$W/corpus/cache/$2"; label=$3
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
mkdir -p "$S/w"
start=$(date +%s)
"$bin" "$pdf" "$S/w/$label.epub" --package-identifier urn:uuid:00000000-0000-4000-8000-000000000001 \
  --modification-date 2026-01-01T00:00:00Z > "$S/w/$label.json" 2> "$S/w/$label.err"
rc=$?
sha=$(shasum -a 256 "$S/w/$label.epub" | cut -c1-16)
echo "$sha" > "$S/w/$label.sha"
echo "rc=$rc sha=$sha free=${free}G secs=$(( $(date +%s) - start ))"
python3 "$T/block-dump.py" "$S/w/$label.epub" > "$S/w/$label.txt"
python3 "$T/nav.py" "$S/w/$label.epub" "$S/w/$label"
rm -f "$S/w/$label.epub"
