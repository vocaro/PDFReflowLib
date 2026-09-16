#!/bin/zsh
# Run one converter N times on one source with reproducible bytes; print each output's hash
# and structureFallback page count.
set -u
BIN=$1
SRC=$2
N=$3
OUT=/private/tmp/i67/m/rep
rm -rf $OUT
mkdir -p $OUT
for i in $(seq 1 $N); do
  $BIN "$SRC" "$OUT/r$i.epub" \
    --package-identifier urn:uuid:00000000-0000-4000-8000-000000000001 \
    --modification-date 2026-01-01T00:00:00Z > "$OUT/r$i.json" 2>/dev/null
  H=$(shasum -a 256 "$OUT/r$i.epub" | cut -c1-16)
  F=$(python3 -c "
import json,sys
d=json.load(open('$OUT/r$i.json'))
w=d.get('warnings') or []
print(len({x['page'] for x in w if x['code']=='structureFallback'}), len(w))
")
  echo "run $i  sha=$H  structureFallbackPages/totalWarnings=$F"
done
