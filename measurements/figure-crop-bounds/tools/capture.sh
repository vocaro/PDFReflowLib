#!/bin/zsh
# usage: capture.sh   (run from the worktree root) — builds the capture tool from the working tree
# and writes Tests/PDFReflowLibTests/fixtures/faa-<page>-clipped-layout.json for the #98/#52 pages.
set -e
S=${0:A:h}
xcrun swiftc -parse-as-library -O -swift-version 6 -module-cache-path .build/raster-environment/module-cache \
  Sources/PDFReflowLib/{NativeTextReader,ConversionTypes,DocumentModel,ReflowDocument,GraphicsReader,NativeSpacingReader,StructureTreeReader,MarkedTextReader}.swift \
  tools/capture-layout-fixture.swift -o "$S/bin/capture"
for page in 19 96 130 146 191 351 361 159 401; do
  "$S/bin/capture" faa-phak-8083-25c $page Tests/PDFReflowLibTests/fixtures/faa-$page-clipped-layout.json 2>/dev/null
  ls -la Tests/PDFReflowLibTests/fixtures/faa-$page-clipped-layout.json
done
