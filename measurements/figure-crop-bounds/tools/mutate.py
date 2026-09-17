"""Single-rule mutations of the GraphicsReader change; runs FigureCropBoundsTests for each (from the worktree root)."""
import subprocess

PATH = 'Sources/PDFReflowLib/GraphicsReader.swift'
original = open(PATH).read()
mutants = {
    'paths unclipped': ('guard let shown = visible(path.insetBy(dx: -2, dy: -2)) else { return }',
                        'let shown = path.insetBy(dx: -2, dy: -2)'),
    'images unclipped': ('if let shown = s.visible(CGRect(x: 0, y: 0, width: 1, height: 1).applying(s.matrix)) { s.add(shown) }',
                         's.add(CGRect(x: 0, y: 0, width: 1, height: 1).applying(s.matrix))'),
    'outside keeps extent': ('return shown.isNull || shown.isEmpty ? nil : shown',
                             'return shown.isNull || shown.isEmpty ? rect : shown'),
}
try:
    for name, (old, new) in mutants.items():
        assert original.count(old) == 1, name
        open(PATH, 'w').write(original.replace(old, new))
        run = subprocess.run(['swift', 'test', '--filter', 'FigureCropBoundsTests'], capture_output=True, text=True)
        failed = sorted({l.split('Test ')[1].split('(')[0] for l in run.stdout.splitlines()
                         if l.startswith('✘ Test') and ' failed after' in l})
        summary = [l for l in run.stdout.splitlines() if 'Test run with' in l]
        print(f'{name}: {summary[-1] if summary else run.stderr[-300:]}')
        for test in failed:
            print(f'    fails {test}')
finally:
    open(PATH, 'w').write(original)
