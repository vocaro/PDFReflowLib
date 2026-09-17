#!/bin/bash
# Converts each control with baseline and candidate CLIs (pinned identifiers) and compares content.
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue37
F=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a11a7ffaa3ea102c4/Tests/PDFReflowLibTests/fixtures
df -h /System/Volumes/Data | tail -1
for pair in "warren9:$S/ctl/warren9.pdf" "rotated:$F/rotated.pdf" "scanned:$F/scanned.pdf"; do
  name=${pair%%:*}; pdf=${pair#*:}
  for side in baseline candidate; do
    rm -rf "$S/ctl/$name-$side" "$S/ctl/$name-$side.epub"
    "$S/$side/pdf-reflow" "$pdf" "$S/ctl/$name-$side.epub" --package-identifier urn:uuid:00000000-0000-4000-8000-000000000001 \
      --modification-date 2026-01-01T00:00:00Z 2>/dev/null > "$S/ctl/$name-$side.json"
    mkdir -p "$S/ctl/$name-$side" && unzip -q "$S/ctl/$name-$side.epub" -d "$S/ctl/$name-$side"
  done
  b=$(shasum -a 256 "$S/ctl/$name-baseline.epub" | cut -c1-16); c=$(shasum -a 256 "$S/ctl/$name-candidate.epub" | cut -c1-16)
  rep=$(diff <(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['imageCount'],d['reflowedPageCount'],[(w['page'],w['code']) for w in d['warnings']])" "$S/ctl/$name-baseline.json") \
             <(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['imageCount'],d['reflowedPageCount'],[(w['page'],w['code']) for w in d['warnings']])" "$S/ctl/$name-candidate.json") > /dev/null && echo same || echo DIFFERENT)
  echo "$name epub baseline $b candidate $c; report $rep; $(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print('images',d['imageCount'],'reflowed',d['reflowedPageCount'],'of',d['pageCount'],'warnings',len(d['warnings']))" "$S/ctl/$name-candidate.json")"
  rm -rf "$S/ctl/$name-baseline" "$S/ctl/$name-candidate" "$S/ctl/$name-baseline.epub" "$S/ctl/$name-candidate.epub"
done
