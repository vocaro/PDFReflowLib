import re, sys, os, collections

def tokens(data):
    i, n = 0, len(data)
    while i < n:
        c = data[i:i+1]
        if c in b' \t\r\n\f\x00':
            i += 1; continue
        if c == b'%':
            j = data.find(b'\n', i); i = n if j < 0 else j+1; continue
        if c == b'(':
            depth, j, esc = 1, i+1, False
            while j < n and depth:
                ch = data[j:j+1]
                if esc: esc = False
                elif ch == b'\\': esc = True
                elif ch == b'(': depth += 1
                elif ch == b')': depth -= 1
                j += 1
            yield ('str', data[i:j]); i = j; continue
        if data[i:i+2] == b'<<':
            yield ('op2', '<<'); i += 2; continue
        if data[i:i+2] == b'>>':
            yield ('op2', '>>'); i += 2; continue
        if c == b'<':
            j = data.find(b'>', i); j = n if j < 0 else j+1
            yield ('str', data[i:j]); i = j; continue
        if c == b'/':
            j = i+1
            while j < n and data[j:j+1] not in b' \t\r\n\f\x00/[]<>(){}%': j += 1
            yield ('name', data[i+1:j].decode('latin-1')); i = j; continue
        if c in b'[]{}':
            yield ('op2', c.decode()); i += 1; continue
        j = i
        while j < n and data[j:j+1] not in b' \t\r\n\f\x00/[]<>(){}%': j += 1
        tok = data[i:j].decode('latin-1'); i = j
        if re.fullmatch(r'[-+.0-9]+', tok):
            try: yield ('num', float(tok)); continue
            except ValueError: pass
        yield ('kw', tok)

class Res:
    def __init__(self): self.reasons = collections.Counter(); self.unknown = collections.Counter()

def scan(data, res):
    stack = []
    marks = []        # list of (id, artifact)
    intext = False
    positioned = False
    depth_arr = 0
    for kind, val in tokens(data):
        if kind in ('num','str','name'):
            stack.append((kind,val)); continue
        if kind == 'op2':
            stack.append((kind,val)); continue
        op = val
        if op == 'BT': intext = True; positioned = True
        elif op == 'ET': intext = False; positioned = False
        elif op in ('Tm',): positioned = True
        elif op in ('Td','TD','T*',"'"): positioned = True if op != "'" else True
        elif op in ('Tj','TJ','"',"'"):
            known = positioned
            if op == 'TJ':
                # find first element of last array
                # locate matching '[' from end
                k = len(stack)-1
                if k >= 0 and stack[k] == ('op2',']'):
                    j = k-1
                    while j >= 0 and stack[j] != ('op2','['): j -= 1
                    if j >= 0 and j+1 < k and stack[j+1][0]=='num' and stack[j+1][1] != 0:
                        known = False
            if op == "'" or op == '"': known = True
            cur = marks[-1] if marks else (None, False)
            if not known:
                cause = 'no-positioning' if not positioned else 'leading-TJ-adjustment'
                if cur[0] is not None: res.unknown['mcid/'+cause] += 1
                elif cur[1]: res.unknown['artifact/'+cause] += 1
                else:
                    res.unknown['unmarked/'+cause] += 1
                    res.reasons['unmarked-unknown-origin'] += 1
            positioned = False
        elif op == 'BDC':
            # operands: name, property(dict or name)
            label = None
            mcid = None
            # find the tag name: first 'name' operand
            names = [v for k,v in stack if k=='name']
            if names: label = names[0]
            # mcid
            txt = ' '.join(str(v) for k,v in stack)
            m = re.search(r'MCID\s+([-0-9.]+)', txt)
            if m:
                try: mcid = int(float(m.group(1)))
                except ValueError: mcid = None
            inherited = marks[-1] if marks else (None, False)
            if label == 'Artifact': marks.append((None, True))
            elif mcid is not None: marks.append((mcid, False))
            else: marks.append(inherited)
        elif op == 'BMC':
            names = [v for k,v in stack if k=='name']
            label = names[0] if names else None
            inherited = marks[-1] if marks else (None, False)
            marks.append((None, True) if label=='Artifact' else inherited)
        elif op == 'EMC':
            if marks: marks.pop()
            else: res.reasons['emc-underflow'] += 1
        elif op == 'q': stack_q = True
        elif op == 'Do':
            names = [v for k,v in stack if k=='name']
            res.reasons['Do:'+ (names[0] if names else '?')] += 0
        stack = []
    if marks: res.reasons['unbalanced-marks'] += 1
    if intext: res.reasons['unbalanced-BT'] += 1

d = sys.argv[1]
tot = collections.Counter(); totr = collections.Counter()
per = {}
for i in range(1,136):
    p = os.path.join(d, 'p%d.txt' % i)
    res = Res()
    scan(open(p,'rb').read(), res)
    per[i] = res
    tot.update(res.unknown); totr.update(res.reasons)
print('unknown-origin shows by mark context:', dict(tot))
print('reasons:', {k:v for k,v in totr.items() if v})
pages_with_unmarked = [i for i in per if per[i].unknown['unmarked']]
pages_with_mcid = [i for i in per if per[i].unknown['mcid']]
pages_with_art = [i for i in per if per[i].unknown['artifact']]
print('pages with unmarked unknown-origin:', len(pages_with_unmarked), pages_with_unmarked[:20])
print('pages with mcid unknown-origin:', len(pages_with_mcid), pages_with_mcid[:20])
print('pages with artifact unknown-origin:', len(pages_with_art), pages_with_art[:20])
