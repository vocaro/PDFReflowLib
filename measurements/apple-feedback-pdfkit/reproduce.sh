#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# Full Xcode must be selected (xcode-select -p), or set DEVELOPER_DIR.
xcrun swiftc -O -g probe.swift -o probe
codesign --force --sign - --entitlements debug-entitlements.plist probe
./probe faa-h-8083-25c.pdf plain 3 > plain-reproduced.jsonl 2> plain-reproduced-stderr.txt
./probe faa-h-8083-25c.pdf page 3 > page-reproduced.jsonl 2> page-reproduced-stderr.txt
# leaks may return nonzero when it finds a leak. Inspect the report rather than treating
# that status alone as an instrumentation failure.
MallocStackLogging=1 /usr/bin/leaks --atExit -- ./probe faa-h-8083-25c.pdf page 1 > leaks-reproduced.txt 2>&1
