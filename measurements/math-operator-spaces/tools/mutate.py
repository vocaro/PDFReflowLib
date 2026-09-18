#!/usr/bin/env python3
"""usage: mutate.py [name...]

Applies each mutation to its source file, rebuilds the tests, runs NativeSpacingTests and prints
the failing tests; the source is restored after every run and compared byte for byte with the
original. A mutation whose text is not found once is an error."""
import hashlib
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
READER = "Sources/PDFReflowLib/NativeSpacingReader.swift"
LAYOUT = "Sources/PDFReflowLib/LayoutReconstructor.swift"
MUTATIONS = {
    "no-in-show": (READER, "operatorSpace(left: scalars[before], right: scalars[index], gap: gap)",
                   "false && operatorSpace(left: scalars[before], right: scalars[index], gap: gap)"),
    "no-cross-show": (READER, "operatorSpace(left: left, right: right, gap: (show.origin.x - end)",
                      "false && operatorSpace(left: left, right: right, gap: (show.origin.x - end)"),
    "threshold-0.1": (READER, "static let operatorSpaceGap: CGFloat = 0.15", "static let operatorSpaceGap: CGFloat = 0.1"),
    "no-em-cap": (READER, "gap >= operatorSpaceGap, gap <= 1,", "gap >= operatorSpaceGap,"),
    "no-sign-pairs": (READER, "mathOperators.contains(left) || mathOperators.contains(right) else",
                      "mathOperators.contains(left) != mathOperators.contains(right) else"),
    "producer-condition": (READER, "for boundary in boundaries where boundary.offset > 0 && boundary.offset < unicode.utf16.count {\n                    let index",
                           "for boundary in boundaries where (spacing.0 != 0 || spacing.1 != 0) && boundary.offset > 0 && boundary.offset < unicode.utf16.count {\n                    let index"),
    "hyphen-is-a-sign": (READER, "static let mathOperators = Set(\"+", "static let mathOperators = Set(\"-+"),
    "signs-count-as-tokens": (LAYOUT, "(share.tokens - signs) * 2", "share.tokens * 2 + signs * 0"),
}


def run(name):
    path, old, new = MUTATIONS[name]
    full = os.path.join(ROOT, path)
    original = open(full, "rb").read()
    digest = hashlib.sha256(original).hexdigest()
    text = original.decode()
    if text.count(old) != 1:
        raise SystemExit(f"{name}: pattern found {text.count(old)} times")
    try:
        open(full, "w").write(text.replace(old, new))
        build = subprocess.run(["swift", "build", "--build-tests"], cwd=ROOT, capture_output=True, text=True)
        if build.returncode:
            print(f"{name}: BUILD FAILED\n{build.stdout[-2000:]}")
            return
        test = subprocess.run(["swift", "test", "--skip-build", "--filter", "NativeSpacingTests"], cwd=ROOT,
                              capture_output=True, text=True)
        failing = sorted(set(re.findall(r"✘ Test (\w+)\(\) failed", test.stdout + test.stderr)))
        print(f"{name}: {len(failing)} failing: {', '.join(failing) or 'NONE'}", flush=True)
    finally:
        open(full, "wb").write(original)
        assert hashlib.sha256(open(full, "rb").read()).hexdigest() == digest, f"{path} not restored"


for name in sys.argv[1:] or MUTATIONS:
    run(name)
