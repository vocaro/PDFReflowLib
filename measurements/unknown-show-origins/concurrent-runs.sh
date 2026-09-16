#!/bin/zsh
# Three concurrent conversions of the same source with the same binary, then compare bytes.
set -u
BIN=$1
SRC=$2
OUT=/private/tmp/i67/m/conc
rm -rf $OUT
mkdir -p $OUT
for i in 1 2 3; do
  $BIN "$SRC" "$OUT/c$i.epub" \
    --package-identifier urn:uuid:00000000-0000-4000-8000-000000000001 \
    --modification-date 2026-01-01T00:00:00Z > "$OUT/c$i.json" 2>/dev/null &
done
wait
for i in 1 2 3; do
  H=$(shasum -a 256 "$OUT/c$i.epub" | cut -c1-16)
  F=$(python3 -c "
import json
d=json.load(open('$OUT/c$i.json'))
w=d.get('warnings') or []
print(len({x['page'] for x in w if x['code']=='structureFallback'}), len(w))
")
  echo "concurrent $i  sha=$H  structureFallbackPages/totalWarnings=$F"
done
