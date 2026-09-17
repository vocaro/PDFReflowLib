#!/bin/zsh
# usage: survey.sh <base-label> <cand-label> <pdf>   — runs both survey binaries and the analysis
S=${0:A:h:h}
cd $S
for s in $1 $2; do
  rm -f survey-$s.jsonl
  bin/survey-$s $3 1 522 survey-$s.jsonl 2>/dev/null
  echo "== $s"
  python3 tools/analyze.py survey-$s.jsonl $s-faa-phak-8083-25c/faa-phak-8083-25c/faa-phak-8083-25c.epub 2>&1 | head -4
  python3 tools/analyze.py survey-$s.jsonl $s-faa-phak-8083-25c/faa-phak-8083-25c/faa-phak-8083-25c.epub --list figure-crop > lf-$s.txt 2>&1
  python3 tools/analyze.py survey-$s.jsonl $s-faa-phak-8083-25c/faa-phak-8083-25c/faa-phak-8083-25c.epub --list formula-or-table-crop > lm-$s.txt 2>&1
done
cmp -s list-fig-base43.txt lf-$1.txt && cmp -s list-form-base43.txt lm-$1.txt && echo "base lists identical to 43b20aa"
cmp -s list-fig-c4.txt lf-$2.txt && cmp -s list-form-c4.txt lm-$2.txt && echo "candidate lists identical to 43b20aa"
