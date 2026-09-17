#!/bin/sh
# usage: measurements/font-weight-detection/tools/capture.sh <capture-layout-fixture binary>
# Recaptures the #125 source fixtures (runs carry `bold`) from the repository root.
set -eu
capture=$1
fixtures=Tests/PDFReflowLibTests/fixtures
for spec in fed-explained-2021:46:fed-46 fed-explained-2021:66:fed-66 gpo-911-2004:19:911-19 gpo-911-2004:44:911-44 \
            gpo-911-2004:62:911-62 gpo-our-flag-2003:7:flag-7 wallace-algebra-2010:7:algebra-7 dga-2025-2030:3:dga-3; do
    case_id=${spec%%:*}; rest=${spec#*:}; page=${rest%%:*}; name=${rest#*:}
    "$capture" "$case_id" "$page" "$fixtures/$name-weights-layout.json" 2>/dev/null
done
