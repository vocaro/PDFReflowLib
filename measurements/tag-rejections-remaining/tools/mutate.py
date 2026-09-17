"""mutate.py <baseline MarkedTextReader.swift>: run TaggedRejectionsRemainingTests against the d63bbbc reader and
against the candidate with one part of the #91 change removed at a time; the source is restored after each run."""
import re, subprocess, sys
from pathlib import Path
root = Path(__file__).resolve().parents[3]
source = root / 'Sources/PDFReflowLib/MarkedTextReader.swift'
original = source.read_text()
mutations = {
    'baseline reader (d63bbbc)': None,
    'space-only shows are not ignored': ('            if blank && !empty {', '            if false && blank && !empty {'),
    'blank identifiers do not count as shown': ('        found.formUnion(s.blankIdentifiers)\n', ''),
    'no codespace normalisation': ('            text = text.replacingOccurrences(of:', '            _ = text.replacingOccurrences(of:'),
    'font not restored by Q': ('(s.matrix, s.leading, s.rise, s.spaces, s.renderMode) = saved', '(s.matrix, s.leading, s.rise, _, s.renderMode) = saved'),
    'render mode not restored by Q': ('(s.matrix, s.leading, s.rise, s.spaces, s.renderMode) = saved', '(s.matrix, s.leading, s.rise, s.spaces, _) = saved'),
    'invisible text refused everywhere': ('if renderMode == 3, marks.last?.artifact != true { invalid = true; return }', 'if renderMode == 3 { invalid = true; return }'),
    'invisible text never refused': ('if renderMode == 3, marks.last?.artifact != true { invalid = true; return }', ''),
    'Tr 3 still refused when set': ('[0, 1, 2, 3].contains(n[0])', '[0, 1, 2].contains(n[0])'),
    'any Tr accepted': ('[0, 1, 2, 3].contains(n[0])', '(0...7).contains(n[0])'),
    'Type3 fonts treated as simple': ('["Type1", "TrueType", "MMType1"].contains(subtype)', '["Type1", "TrueType", "MMType1", "Type3"].contains(subtype)'),
    'no-map fonts assume code 32 is a space': ('["WinAnsiEncoding", "MacRomanEncoding", "StandardEncoding"].contains(encoding) else { return [] }',
                                               '["WinAnsiEncoding", "MacRomanEncoding", "StandardEncoding"].contains(encoding) else { return [0x20] }'),
    'map value other than U+0020 counts': ('map.filter { $0.value == " " }.keys', 'map.keys.filter { $0 == 0x20 }'),
}
try:
    for name, change in mutations.items():
        if change is None:
            source.write_text(Path(sys.argv[1]).read_text())
        else:
            assert original.count(change[0]) == 1, name
            source.write_text(original.replace(*change))
        run = subprocess.run(['swift', 'test', '--filter', 'TaggedRejectionsRemainingTests'], cwd=root, capture_output=True, text=True)
        out = run.stdout + run.stderr
        failing = sorted(set(re.findall(r'✘ Test (\w+)\(', out)))
        summary = re.findall(r'[✔✘] Test run with .*', out)
        print(f'{name}: exit {run.returncode}; failing {failing}; {summary[-1] if summary else "no summary"}', flush=True)
finally:
    source.write_text(original)
