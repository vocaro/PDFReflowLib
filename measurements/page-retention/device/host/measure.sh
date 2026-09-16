#!/bin/sh
# Physical-device retention measurement for issue #15 (see ../../record.md).
# usage: measure.sh <warren|noaa> <resident|spill|reextract> [udid]
# Needs an Xcode account for the signing team (TEAM env) so automatic provisioning can
# register the device, and an unlocked phone. Sources are staged from corpus/cache at build
# time and removed afterwards; they are never committed.
set -eu
CASE="$1"; RETENTION="$2"; UDID="${3:-00008150-00164DE1342B401C}"
TEAM="${TEAM:-UWX5KMH446}"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
DERIVED="${DERIVED:-/tmp/pdfreflow-device-host}"
OUT="${OUT:-/tmp/pdfreflow-device-results}"; mkdir -p "$OUT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
APP="$DERIVED/Build/Products/Release-iphoneos/RetentionHost.app"
BUNDLE=com.vocaro.pdfreflow.retentionhost
if [ ! -d "$APP" ] || [ "${REBUILD:-0}" = 1 ]; then
    cp "$ROOT/corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf" "$HERE/RetentionHost/warren.pdf"
    cp "$ROOT/corpus/cache/noaa_61592_DS1.pdf" "$HERE/RetentionHost/noaa.pdf"
    trap 'rm -f "$HERE/RetentionHost/warren.pdf" "$HERE/RetentionHost/noaa.pdf"' EXIT
    xcodebuild build -project "$HERE/RetentionHost.xcodeproj" -scheme RetentionHost \
        -configuration Release -destination "platform=iOS,id=$UDID" -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" > "$OUT/build.log" 2>&1 \
        || { grep -E "error:" "$OUT/build.log" | tail -5; exit 65; }
    xcrun devicectl device install app --device "$UDID" "$APP" --quiet
fi
LOG="$OUT/$CASE-$RETENTION.log"
# One strategy per process: the library reads PDFREFLOW_PAGE_RETENTION itself.
xcrun devicectl device process launch --device "$UDID" --console --terminate-existing \
    --environment-variables "{\"PDFREFLOW_DEVICE_CASE\":\"$CASE\",\"PDFREFLOW_PAGE_RETENTION\":\"$RETENTION\"}" \
    "$BUNDLE" > "$LOG" 2>&1 || true
grep -E "PDFREFLOW_DEVICE_(START|RESULT|ERROR)" "$LOG" | sort -u || { echo "no result lines; see $LOG"; exit 1; }
