#!/bin/bash
# usage: build-all.sh : census-base (baseline sources archived at scratchpad/base), census-cand (this tree),
# census-gs (this tree, experiment accepting an ExtGState without Font)
set -e
T=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$T/../../.." && pwd)
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/spacing-maps
"$T/build-census.sh" "$S/base" "$S/bin/census-base"
"$T/build-census.sh" "$W" "$S/bin/census-cand"
"$T/build-census.sh" "$W" "$S/bin/census-gs" --accept-textless-gs
ls "$S/bin"
