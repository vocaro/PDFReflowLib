import subprocess, sys, os, re, json

W = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a1a8c9518159e03c1'
TINT = os.path.join(W, 'Sources/PDFReflowLib/TintDetector.swift')
LAYOUT = os.path.join(W, 'Sources/PDFReflowLib/LayoutReconstructor.swift')
READER = os.path.join(W, 'Sources/PDFReflowLib/GraphicsReader.swift')

MUTATIONS = [
    ('blockText: two lines make a block', TINT,
     '$0.lines.count >= 3 && ($0.lines.filter(readsAsProse).count >= 2',
     '$0.lines.count >= 2 && ($0.lines.filter(readsAsProse).count >= 2'),
    ('blockText: one prose line is enough', TINT,
     '($0.lines.filter(readsAsProse).count >= 2 || $0.lines.filter(wraps).count >= 2)',
     '($0.lines.filter(readsAsProse).count >= 1 || $0.lines.filter(wraps).count >= 2)'),
    ('blockText: one wrapped line is enough', TINT,
     '|| $0.lines.filter(wraps).count >= 2)', '|| $0.lines.filter(wraps).count >= 1)'),
    ('blockText: a wrapped line needs no words', TINT,
     '''&& text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count >= 2''',
     '''&& text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count >= 0'''),
    ('blockText: any left edge joins a block', TINT,
     'abs(line.rect.minX - block.edge) <= size * 3', 'abs(line.rect.minX - block.edge) <= size * 30'),
    ('blockText: any leading joins a block', TINT,
     'last.rect.minY - line.rect.maxY <= size * 0.9 && last.rect.minY > line.rect.minY',
     'last.rect.minY - line.rect.maxY <= size * 9 && last.rect.minY > line.rect.minY'),
    ('clustering: text does not keep parts apart', TINT,
     'guard !escaped.contains(where: { $0.rect.intersects(union) }) else { continue }',
     'guard true else { continue }'),
    ('clustering: a part holding the line does not keep it', TINT,
     'line.rect.intersects(hull) && !members.contains { $0.intersects(line.rect) }',
     'line.rect.intersects(hull)'),
    ('backdrops: one prose line makes a background', TINT,
     'if text.count >= 3, text.count * 3 >= inside.count {', 'if text.count >= 1, text.count * 3 >= inside.count {'),
    ('backdrops: a covered picture is kept', TINT,
     'if area(rest) < area(rect) / 2 || coverage(of: rest, by: others) >= 0.9 {',
     'if area(rest) < area(rect) / 20 || coverage(of: rest, by: others) >= 0.9 {'),
    ('backdrops: a picture under another is kept', TINT,
     '|| coverage(of: rest, by: others) >= 0.9 {', '|| coverage(of: rest, by: others) >= 2 {'),
    ('backdrops: text inside a picture is treated as running on', TINT,
     'if continues(text, beyond: rect, lines: lines) {', 'if true {'),
    ('backdrops: any line trims a picture', TINT,
     'where !mostlyInside(line.rect, rect) && (prose(line) || title(line)) && kept.intersects(line.rect)',
     'where !mostlyInside(line.rect, rect) && kept.intersects(line.rect)'),
    ('backdrops: a picture may give up most of itself', TINT,
     'if kept != rect, area(kept) >= area(rect) / 2 { result[index].rect = kept }',
     'if kept != rect, area(kept) >= 0 { result[index].rect = kept }'),
    ('bands: one line makes a caption band', TINT,
     'return held.count >= 2 && held.contains(where: readsAsProse)',
     'return held.count >= 1 && held.contains(where: readsAsProse)'),
    ('bands: a band holding art is still a band', TINT,
     '&& !paints.contains { $0.rect != paint.rect && !$0.image && paint.rect.contains($0.rect) }',
     ''),
    ('banner: a narrow band is a banner', TINT,
     'guard hull.width >= bounds.width * 0.8, inside.count >= 2,',
     'guard hull.width >= bounds.width * 0.1, inside.count >= 2,'),
    ('banner: a band anywhere on the page', TINT,
     'hull.minY <= bounds.minY + hull.height || hull.maxY >= bounds.maxY - hull.height,', 'true,'),
    ('banner: any row reads', TINT, 'guard words >= 3 || title else { return false }', 'guard true else { return false }'),
    ('banner: no title needed', TINT, 'return holdsTitle', 'return true'),
    ('panels: one block line makes a panel', TINT,
     '} else if !tinted.isEmpty, block.count >= 3, oneColumnOfText(inside, block: block, body: body),',
     '} else if !tinted.isEmpty, block.count >= 1, oneColumnOfText(inside, block: block, body: body),'),
    ('panels: columns of fragments are one column', TINT,
     'return inside.allSatisfy { abs($0.rect.minX - edge) <= body * 3 }', 'return true'),
    ('panels: a ruled grid is a panel', TINT,
     'hull.insetBy(dx: -body, dy: -body).contains($0) }).count < 2 {',
     'hull.insetBy(dx: -body, dy: -body).contains($0) }).count < 99 {'),
    ('crops: a grazing corner captures a line', LAYOUT,
     'guard !overlap.isNull, overlap.width >= 1, overlap.height >= 1 else { return false }',
     'guard !overlap.isNull else { return false }'),
    ('crops: a text cut may eat the art', LAYOUT,
     '&& cut.insetBy(dx: -0.01, dy: -0.01).contains(ink)', ''),
    ('crops: regions merge across running text', LAYOUT,
     '''if !existing.bounds.intersects(merged.bounds),
                           text.contains(where: { line in
                               line.rect.intersects(union) && !line.rect.intersects(merged.bounds)
                                   && !line.rect.intersects(existing.bounds)
                           }) { return false }''', ''),
    ('reader: a covered group box is still recorded', READER,
     'if rect.isFinite, !covered,', 'if rect.isFinite,'),
    ('reader: a page-wide gradient keeps the page image', READER,
     '''        s.add(region.insetBy(dx: -2, dy: -2).intersection(s.pageBounds))
    }''',
     '''        guard region.width * region.height < s.pageBounds.width * s.pageBounds.height * 0.75 else {
            s.unsupported = true; return
        }
        s.add(region.insetBy(dx: -2, dy: -2).intersection(s.pageBounds))
    }'''),
]

def run_tests():
    result = subprocess.run(['swift', 'test'], cwd=W, capture_output=True, text=True)
    failures = re.findall(r'✘ Test (\w+)\(\) recorded an issue', result.stdout + result.stderr)
    build_error = 'error:' in result.stdout or 'error:' in result.stderr
    return sorted(set(failures)), build_error

log = open('/private/tmp/claude-501/i158/mutants.log', 'w')
survivors = []
only = sys.argv[1:]
for index, (label, path, old, new) in enumerate(MUTATIONS):
    if only and str(index) not in only:
        continue
    source = open(path).read()
    if old not in source:
        print(f'{index}: {label}: PATTERN MISSING', file=log, flush=True)
        print(f'{index}: {label}: PATTERN MISSING')
        survivors.append(label)
        continue
    open(path, 'w').write(source.replace(old, new, 1))
    try:
        failures, build_error = run_tests()
    finally:
        open(path, 'w').write(source)
    state = 'BUILD ERROR' if build_error and not failures else ('killed by ' + ', '.join(failures[:4]) if failures else 'SURVIVED')
    print(f'{index}: {label}: {state}', file=log, flush=True)
    print(f'{index}: {label}: {state}')
    if not failures:
        survivors.append(label)
print('survivors:', survivors, file=log, flush=True)
print('survivors:', survivors)
