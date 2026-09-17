import re, sys
p = sys.argv[1] + '/GraphicsReader.swift'
s = open(p).read()
def rep(a, b, count=1):
    global s
    assert s.count(a) >= 1, a
    s = s.replace(a, b) if count == 0 else s.replace(a, b, count)
rep('struct Paint: Equatable, Sendable { var rect: CGRect; var frame: Bool }',
    'struct Paint: Equatable, Sendable { var rect: CGRect; var frame: Bool; var kind: UInt8 = 0 }')
rep('func add(_ rect: CGRect, frame: Bool = false) {\n            if paints.count < 10_000 { paints.append(Paint(rect: rect, frame: frame)) }',
    'func add(_ rect: CGRect, frame: Bool = false, kind: UInt8 = 0) {\n            if paints.count < 10_000 { paints.append(Paint(rect: rect, frame: frame, kind: kind)) }')
rep('.applying(s.matrix)) { s.add(shown) }', '.applying(s.matrix)) { s.add(shown, kind: 1) }')
rep('                            s.add(rect)\n', '                            s.add(rect, kind: 2)\n')
rep('s.add(region.insetBy(dx: -2, dy: -2).intersection(s.pageBounds))', 's.add(region.insetBy(dx: -2, dy: -2).intersection(s.pageBounds), kind: 3)')
rep('Paint(rect: visible, frame: paint.frame)', 'Paint(rect: visible, frame: paint.frame, kind: paint.kind)')
open(p, 'w').write(s)
