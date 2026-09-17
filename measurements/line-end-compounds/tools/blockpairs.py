import sys, re, zipfile
# Consecutive block elements where the first ends in a hyphen and the second opens lowercase.
prefix = sys.argv[1]
pat = re.compile(r'([^<>]{0,60}-)</(p|pre|li|h[1-6])>\s*(?:<[^>]*page[^>]*>\s*(?:</[^>]+>)?\s*)*<(p|pre|li|h[1-6])(?: [^>]*)?>(?:<[^>]+>)*([^<]{0,60})')
for case in sys.argv[2:]:
    path = f'{prefix}-{case}/{case}/{case}.epub'
    n = 0
    with zipfile.ZipFile(path) as z:
        for name in sorted(z.namelist()):
            if not name.endswith('.xhtml'): continue
            t = z.read(name).decode()
            for m in pat.finditer(t):
                right = m.group(4)
                if right[:1].islower() or right[:1].isdigit() or right[:1].isupper():
                    n += 1
                    print(f'{case}\t{name}\t{m.group(2)}->{m.group(3)}\t{m.group(1)[-40:]!r} | {right[:40]!r}')
    print('#', case, n, file=sys.stderr)
