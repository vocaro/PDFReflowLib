#!/bin/bash
# usage: recapture.sh <page>...  recapture Fed layout fixtures to the scratch directory and diff them
# against the committed fixtures (Tests/PDFReflowLibTests/fixtures/fed-<page>-layout.json).
T=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$T/../../.." && pwd)
S=${ISSUE65_SCRATCH:?set ISSUE65_SCRATCH}
cd "$W"
swiftc Sources/PDFReflowLib/NativeTextReader.swift Sources/PDFReflowLib/ConversionTypes.swift \
  Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
  Sources/PDFReflowLib/GraphicsReader.swift Sources/PDFReflowLib/NativeSpacingReader.swift \
  Sources/PDFReflowLib/StructureTreeReader.swift Sources/PDFReflowLib/MarkedTextReader.swift \
  tools/capture-layout-fixture.swift -o "$S/bin/capture" || exit 1
for n in "$@"; do
  "$S/bin/capture" fed-explained-2021 "$n" "$S/fed-$n-new.json" 2>/dev/null
  echo "== fed-$n"
  python3 "$T/fixturediff.py" "Tests/PDFReflowLibTests/fixtures/fed-$n-layout.json" "$S/fed-$n-new.json"
done
