#!/bin/bash
set -e
H="$(cd "$(dirname "$0")" && pwd)"
SRC=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a11a7ffaa3ea102c4/Sources/PDFReflowLib
FILES=()
for f in "$SRC"/*.swift; do
  case "$(basename "$f")" in EPUBWriter.swift|PDFConverter.swift) ;; *) FILES+=("$f");; esac
done
MAIN="${1:-main.swift}"
OUT="${2:-harness}"
mkdir -p "$H/build-$OUT"
cp "$H/$MAIN" "$H/build-$OUT/main.swift"
swiftc -O -swift-version 6 -enable-bare-slash-regex -o "$H/$OUT" "${FILES[@]}" "$H/build-$OUT/main.swift"
