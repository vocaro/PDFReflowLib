#!/bin/sh
# Repeated in-process conversions for issue #4 (see record.md).
# usage: measure.sh ROUNDS input.pdf...
# SIMULATOR=<udid> runs the harness in that booted iOS Simulator instead of on the Mac.
# LEAKS=1 (Mac only) adds a `leaks` count after every round. Builds the library from this
# checkout in release into a scratch package; nothing is written inside the checkout.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
WORK="${WORK:-${TMPDIR:-/tmp}/pdfreflow-repeated-conversions}"
mkdir -p "$WORK/Sources/Harness"
cp "$HERE/harness.swift" "$WORK/Sources/Harness/main.swift"
IDENTITY=$(basename "$ROOT" | tr '[:upper:]' '[:lower:]')
cat > "$WORK/Package.swift" <<EOF
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Harness",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    dependencies: [.package(path: "$ROOT")],
    targets: [.executableTarget(name: "Harness", dependencies: [.product(name: "PDFReflowLib", package: "$IDENTITY")])]
)
EOF
ROUNDS="$1"; shift
if [ -n "${SIMULATOR:-}" ]; then
    SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
    swift build -c release --package-path "$WORK" --scratch-path "$WORK/.build-sim" \
        --triple arm64-apple-ios27.0-simulator --sdk "$SDK" > "$WORK/build.log" 2>&1 \
        || { grep -E "error:" "$WORK/build.log" | tail -5; exit 65; }
    xcrun simctl spawn "$SIMULATOR" "$WORK/.build-sim/release/Harness" "$ROUNDS" "$WORK/output" "$@"
else
    swift build -c release --package-path "$WORK" > "$WORK/build.log" 2>&1 \
        || { grep -E "error:" "$WORK/build.log" | tail -5; exit 65; }
    "$WORK/.build/release/Harness" "$ROUNDS" "$WORK/output" "$@" 2> /dev/null
fi
rm -rf "$WORK/output"
