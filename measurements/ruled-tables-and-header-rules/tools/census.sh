#!/bin/bash
# usage: census.sh <case-id>...  compile census.swift with the reader sources and write census-<case>.txt
T=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$T/../../.." && pwd)
S=${ISSUE65_SCRATCH:?set ISSUE65_SCRATCH}
cd "$W"
swiftc -O Sources/PDFReflowLib/NativeTextReader.swift Sources/PDFReflowLib/ConversionTypes.swift \
  Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
  Sources/PDFReflowLib/GraphicsReader.swift Sources/PDFReflowLib/NativeSpacingReader.swift \
  Sources/PDFReflowLib/StructureTreeReader.swift Sources/PDFReflowLib/MarkedTextReader.swift \
  "$T/census.swift" -o "$S/bin/census" || exit 1
for case in "$@"; do
  file=$(python3 -c "import json,sys; print([c['filename'] for c in json.load(open('corpus/manifest.json'))['documents'] if c['id'] == sys.argv[1]][0])" "$case")
  "$S/bin/census" "corpus/cache/$file" 2>/dev/null > "$T/../census-$case.txt"
  echo "$case: $(tail -1 "$T/../census-$case.txt")"
done
