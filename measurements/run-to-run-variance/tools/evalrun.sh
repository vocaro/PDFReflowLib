#!/bin/zsh
# usage: evalrun.sh converter case label [converter options...]
# One evaluation (no EPUBCheck) into runs/<label>; records load before and after, and a summary line.
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a1f4f642d57375727
S=/private/tmp/claude-501/i140
conv=$1; case=$2; label=$3; shift 3
file=$(python3 -c "import json,sys; print(next(d['filename'] for d in json.load(open('$W/corpus/manifest.json'))['documents'] if d['id']=='$case'))")
opts=(--converter-option=--package-identifier=urn:uuid:00000000-0000-4000-8000-000000000001
      --converter-option=--modification-date=2026-01-01T00:00:00Z)
for o in "$@"; do opts+=(--converter-option=$o); done
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 8 ]; then echo "STOP: only ${free} GiB free"; exit 2; fi
out=$S/runs/$label
echo "load-before $(uptime | sed 's/.*averages: //')" > $S/runs/$label.load
python3 $W/tools/evaluate-real-document.py --case $case --pdf $W/corpus/cache/$file --converter $conv \
  --output $out --max-peak-rss-mib 4096 --execution-context i140 $opts > /dev/null 2>&1
echo "load-after $(uptime | sed 's/.*averages: //')" >> $S/runs/$label.load
python3 $S/tools/summarize.py $out $S/runs/$label.load
