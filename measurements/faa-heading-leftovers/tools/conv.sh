#!/bin/bash
# usage: conv.sh <label> <binary-label> <pdf>   pinned conversion -> dumps/<label>.txt; EPUB deleted
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a397b1066057391a4
I=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue97
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
echo "free=${free}G"
if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
mkdir -p "$I/out" "$I/dumps"
cd "$W"
start=$(date +%s)
"$I/bin/pdf-reflow-$2" "corpus/cache/$3" "$I/out/$1.epub" --package-identifier urn:uuid:00000000-0000-4000-8000-000000000001 \
  --modification-date 2026-01-01T00:00:00Z > "$I/out/$1.log" 2>&1
echo "rc=$? seconds=$(( $(date +%s) - start ))"
shasum -a 256 "$I/out/$1.epub" | cut -c1-16
python3 measurements/heading-placement/block-dump.py "$I/out/$1.epub" > "$I/dumps/$1.txt"
echo "headings: $(grep -c '^h[1-6]:' "$I/dumps/$1.txt")"
if [ "$4" != "keep" ]; then rm -f "$I/out/$1.epub"; fi
