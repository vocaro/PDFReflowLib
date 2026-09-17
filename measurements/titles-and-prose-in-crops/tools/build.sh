#!/bin/zsh
# usage: build.sh <survey-binary> <capture-binary>  (run from the worktree root)
set -e
D=${0:A:h}
sed -i '' "s#/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-aaf0cc0e6019a1210/tools#$PWD/tools#" "$D/analyze.py"
files=(${(f)"$(ls Sources/PDFReflowLib/*.swift | grep -v 'EPUBWriter\|PDFConverter')"})
xcrun swiftc -parse-as-library -O -swift-version 6 -module-cache-path .build/raster-environment/module-cache "${files[@]}" "$D/survey.swift" -o "$1"
if [[ -n "$2" ]]; then
xcrun swiftc -parse-as-library -O -swift-version 6 -module-cache-path .build/raster-environment/module-cache \
  Sources/PDFReflowLib/{NativeTextReader,ConversionTypes,DocumentModel,ReflowDocument,GraphicsReader,NativeSpacingReader,StructureTreeReader,MarkedTextReader}.swift \
  tools/capture-layout-fixture.swift -o "$2"
fi
