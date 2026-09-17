#!/bin/bash
# usage: one.sh <binary> <pdf-path> <label>  -> w3/<label>.txt (block dump), .json; EPUB deleted
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/w3
bin=$1; pdf=$2; label=$3
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
"$bin" "$pdf" "$S/$label.epub" --package-identifier urn:uuid:00000000-0000-4000-8000-000000000001 \
  --modification-date 2026-01-01T00:00:00Z > "$S/$label.json" 2> "$S/$label.err"
echo "rc=$? sha=$(shasum -a 256 "$S/$label.epub" | cut -c1-16) free=${free}G"
python3 "$S/dump.py" "$S/$label.epub" > "$S/$label.txt"
rm -f "$S/$label.epub" "$S/$label.err"
