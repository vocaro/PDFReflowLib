#!/usr/bin/env python3
"""usage: mutate.py [name...]  (run from the repository root)

Applies each mutation to Sources/PDFReflowLib/NativeSpacingReader.swift, runs the NativeSpacing tests and
prints which tests fail; the reader is restored after every mutation, whatever happens."""
import re
import subprocess
import sys

PATH = "Sources/PDFReflowLib/NativeSpacingReader.swift"
MUTATIONS = {
    # a capital followed by a period no longer blocks a sentence space (`U.|S.`)
    "no-initial": ('guard CharacterSet.uppercaseLetters.contains(right), next != "." else', 'guard CharacterSet.uppercaseLetters.contains(right) else'),
    # an initial before a short abbreviation (`H.|Doc.`) is split
    "no-abbreviation": ('return !((1...2).contains(initial.count)', 'return true || !((1...2).contains(initial.count)'),
    # apostrophes and closing brackets after a letter count as sentence punctuation
    "no-closer-check": ('if closers.contains(last) { return !body.dropLast().allSatisfy { closers.contains($0) } }', 'if closers.contains(last) { return true }'),
    # a number opening its show is split (`10.|August`)
    "no-list-number": ('if startsShow, body.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) { return false }', ''),
    # show-edge candidates are not completed from neighbouring shows
    "no-edge": ('if !candidates.isEmpty {', 'if false {'),
    # the cross-show sentence rule (`FAA:|Yes.`) is removed
    "no-cross-show": ('if let previous, let end = previous.end, previous.spaced || show.spaced,', 'if false, let previous, let end = previous.end, previous.spaced || show.spaced,'),
    # a measured show no longer positions the next one
    "no-continuation": ('text = text.translatedBy(x: full, y: 0); positioned = true', 'text = text.translatedBy(x: full, y: 0)'),
    # character-spacing column gaps are never read
    "no-column": ('static let characterSpacingColumnGap: CGFloat = 0.5', 'static let characterSpacingColumnGap: CGFloat = 1000'),
    # the two-glyph restriction on column gaps is dropped
    "no-two-glyph": ('if boundaries.isEmpty, glyphStarts.count == 2,', 'if boundaries.isEmpty, glyphStarts.count >= 2,'),
    # chained initials keep the overhang threshold (NOAA `C.|A.`)
    "no-chained": ('&& !chained', ''),
    # lone punctuation after a word gap closes a word
    "no-word-gap": ('return start > 0 && !wordGaps.contains(start)', 'return true'),
    # math punctuation never closes a word at a font change
    "no-math-punctuation": ('word(previous.unicode?.last) || closesWord(previous, start: previousStart) && unicode.first?.isLetter == true,', 'word(previous.unicode?.last),'),
}

original = open(PATH, encoding="utf-8").read()
names = sys.argv[1:] or list(MUTATIONS)
try:
    for name in names:
        old, new = MUTATIONS[name]
        assert original.count(old) == 1, f"{name}: pattern not unique"
        open(PATH, "w", encoding="utf-8").write(original.replace(old, new))
        run = subprocess.run(["swift", "test", "--filter", "NativeSpacingTests"], capture_output=True, text=True)
        output = run.stdout + run.stderr
        failed = sorted(set(re.findall(r"✘ Test (\w+)\(\) failed", output)))
        broken = "error: " in output and not failed
        print(f"{name}\t{'BUILD FAILED' if broken else ', '.join(failed) or 'NONE FAIL'}", flush=True)
finally:
    open(PATH, "w", encoding="utf-8").write(original)
