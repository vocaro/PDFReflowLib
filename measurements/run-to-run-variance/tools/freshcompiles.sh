#!/bin/zsh
# usage: freshcompiles.sh n outfile pdf pages...
# Runs the probe under n names never used before, so Vision compiles its models afresh for each,
# and records each compile's fingerprint with the pages' verdicts.
n=$1; out=$2; pdf=$3; shift 3
S=/private/tmp/claude-501/i140
for i in $(seq 1 $n); do
  name=pdf-reflow-i140x$i
  cp $S/probe/pdf-reflow-i140 $S/probe/$name
  echo "== $name $(date +%T) load: $(uptime | sed 's/.*averages: //')" >> $out
  $S/probe/$name $pdf "$@" 2>/dev/null | cut -f1,3,4 >> $out
  python3 $S/tools/anehash.py $name >> $out
  python3 -c "
import sys; sys.path.insert(0,'/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a1f4f642d57375727/tools')
from conversion_provenance import vision_model_cache as v
c = v('$name'); print('programsSHA256', c['programsSHA256'][:16], 'count', c['programCount'])" >> $out
done
