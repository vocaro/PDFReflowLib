#!/bin/sh
# Builds the probe and runs each PDFKit call in a fresh process on the bundled PDFs.
# Requires a full Xcode installation (xcode-select) or DEVELOPER_DIR.
set -eu
cd "$(dirname "$0")"
swift build -c release 2>&1 | tail -1
PROBE="$(swift build -c release --show-bin-path)/StructureTreeProbe"
echo "environment: $(sw_vers -productVersion) ($(sw_vers -buildVersion)) $(uname -m), $(xcodebuild -version | tr '\n' ' ')"
for pdf in page2-tagged page2-untagged page4-control; do
  echo "== pdfs/$pdf.pdf =="
  for call in count string attributed selection smallselection charbounds thumbnail; do
    "$PROBE" "pdfs/$pdf.pdf" 1 "$call" 2>/dev/null
  done
done
