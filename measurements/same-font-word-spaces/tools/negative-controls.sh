#!/bin/bash
# usage: negative-controls.sh <worktree> <backup-dir> <mutation>...
# For each mutation (mutate.py), mutates NativeSpacingReader.swift, runs the #119 spacing tests and prints the
# failing tests and their issue counts, then restores the reader from <backup-dir>. The backup must hold the
# unmutated reader.
W=$1; B=$2; shift 2
R="$W/Sources/PDFReflowLib/NativeSpacingReader.swift"
T=$(cd "$(dirname "$0")" && pwd)
cmp -s "$B/NativeSpacingReader.swift" "$R" || { echo "reader differs from backup"; exit 2; }
for m in "$@"; do
  python3 "$T/mutate.py" "$R" "$m" || { echo "$m: anchor not found"; cp "$B/NativeSpacingReader.swift" "$R"; exit 2; }
  out=$(swift test --package-path "$W" --filter "nineEleven|sameFontWordSpace|tjAdjustments|noteReference|sourceFontBoundaries|wallaceDigit|fontChange|sourceType3" 2>&1)
  cp "$B/NativeSpacingReader.swift" "$R"
  echo "== $m: $(echo "$out" | grep -E '^✘ Test run|^✔ Test run' | cut -c1-120)"
  echo "$out" | grep -E '^✘ Test .*(failed after|with [0-9]+ issue)' | cut -c1-160
done
cmp -s "$B/NativeSpacingReader.swift" "$R" && echo "reader restored"
