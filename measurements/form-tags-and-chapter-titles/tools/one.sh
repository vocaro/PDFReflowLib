#!/bin/bash
# usage: one.sh <binary-label> <pdf-basename> <out-label>
# -> w/<label>.txt (blocks), .nav (navigation), .json (report), .img (image digests); EPUB deleted
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a85805ea97e861ace
bin="$S/bin/$1"; pdf="$W/corpus/cache/$2"; label=$3
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
mkdir -p "$S/w"
start=$(date +%s)
"$bin" "$pdf" "$S/w/$label.epub" --package-identifier urn:uuid:00000000-0000-4000-8000-000000000001 \
  --modification-date 2026-01-01T00:00:00Z > "$S/w/$label.json" 2> "$S/w/$label.err"
rc=$?
echo "rc=$rc sha=$(shasum -a 256 "$S/w/$label.epub" | cut -c1-16) free=${free}G secs=$(( $(date +%s) - start ))"
python3 "$S/dump.py" "$S/w/$label.epub" > "$S/w/$label.txt"
python3 "$S/nav.py" "$S/w/$label.epub" "$S/w/$label"
rm -f "$S/w/$label.epub"
