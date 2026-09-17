#!/bin/sh
# usage: measurements/font-style-detection/tools/capture.sh <capture-layout-fixture binary>
# Recaptures the #133 source fixtures (runs carry `bold` and `italic`) from the repository root.
set -eu
capture=$1
fixtures=Tests/PDFReflowLibTests/fixtures
for spec in gpo-911-2004:171:911-171 scotus-loper-bright-2024:9:scotus-9 fed-explained-2021:8:fed-8 \
            arxiv-replay-clocks-2023:1:arxiv-1 wallace-algebra-2010:18:algebra-18 wallace-algebra-2010:23:algebra-23 \
            dga-2025-2030:3:dga-3 gpo-our-flag-2003:7:flag-7; do
    case_id=${spec%%:*}; rest=${spec#*:}; page=${rest%%:*}; name=${rest#*:}
    "$capture" "$case_id" "$page" "$fixtures/$name-styles-layout.json" 2>/dev/null
done
