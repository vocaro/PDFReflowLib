import os, subprocess
# Single-guard mutations of the page-40 follow-up; each must fail at least one test.
W = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a1cbbc24d84b92807'
os.chdir(W)
G = 'Sources/PDFReflowLib/GraphicsReader.swift'
T = 'Sources/PDFReflowLib/TintDetector.swift'
S = 'Sources/PDFReflowLib/ShadedTableDetector.swift'
mutants = [
    ('stroke band', G, 'if half.isFinite, half > 2, !pathIsRectangles', 'if false, half.isFinite, half > 2, !pathIsRectangles'),
    ('band only for straight strokes', G, '(path.width == 0) != (path.height == 0)', 'true'),
    ('edging', T, '                    removed.insert(other)\n                }\n            }\n            if let kept', '                }\n            }\n            if let kept'),
    ('bands as tint candidates', T, '+ stroked.map(\\.rect) + shapes + bands', '+ stroked.map(\\.rect) + shapes'),
    ('marker column', S, 'guard !(markers.count >= 2 && markers.allSatisfy', 'guard !(false && markers.allSatisfy'),
    ('titles bound the carved band', T, 'let bounds = block.prose + titles', 'let bounds = block.prose'),
]
filt = 'StrokeBandTitles|NOAAFollowUps|FeatheredGroups|PageBackdrop|ShadedTable|Shading|CropsOverRunningText|IllustratedPage|DGABullets|FigureCrop'
for name, path, old, new in mutants:
    src = open(path).read()
    assert src.count(old) == 1, name
    open(path, 'w').write(src.replace(old, new))
    try:
        r = subprocess.run(['swift', 'test', '--filter', filt], capture_output=True, text=True)
        out = r.stdout + r.stderr
        failed = sorted({l.split('Test ')[1].split('(')[0] for l in out.splitlines() if l.startswith('✘ Test ') and 'recorded' in l})
        print(f'{name}: {"KILLED " + ", ".join(failed) if failed else ("SURVIVED" if "error:" not in out else "BUILD ERROR")}', flush=True)
    finally:
        open(path, 'w').write(src)
