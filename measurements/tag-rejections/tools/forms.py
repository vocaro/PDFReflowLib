"""forms.py <pdf> <pages> : for each page, every `Do` of a Form XObject with its mark context
(unmarked / artifact / MCID) and what the form (recursively) contains: text shows, MCIDs, nested forms."""
import collections, re, subprocess, sys
sys.path.insert(0, '.')
from pdftokens import tokens

pdf = sys.argv[1]
pages = [int(p) for p in sys.argv[2].split(',')]

def show(path, binary=True):
    args = ['mutool', 'show'] + (['-b'] if binary else []) + [pdf, path]
    return subprocess.run(args, capture_output=True).stdout

def resources_xobjects(text):
    """Map /Name -> object number from a printed resource dictionary."""
    block = re.search(rb'/XObject\s*<<(.*?)>>', text, re.S)
    if not block:
        m = re.search(rb'/XObject\s+(\d+)\s+0\s+R', text)
        if m:
            return resources_xobjects(b'/XObject <<' + show(m.group(1).decode(), False) + b'>>')
        return {}
    return {k.decode(): v.decode() for k, v in re.findall(rb'/(\S+?)\s+(\d+)\s+0\s+R', block.group(1))}

cache = {}
def form_summary(obj, depth=0):
    """(shows, mcids, forms, subtype) for an XObject."""
    if obj in cache: return cache[obj]
    head = show(obj, False)
    subtype = re.search(rb'/Subtype\s*/(\w+)', head)
    subtype = subtype.group(1).decode() if subtype else '?'
    if subtype != 'Form' or depth > 8:
        cache[obj] = (0, 0, 0, subtype); return cache[obj]
    data = show(obj)
    names = resources_xobjects(head)
    shows = mcids = forms = 0
    stack = []
    for kind, val in tokens(data):
        if kind != 'kw': stack.append((kind, val)); continue
        if val in ('Tj', 'TJ', "'", '"'): shows += 1
        elif val == 'BDC' and any(k == 'name' and v == 'MCID' for k, v in stack[-8:]): mcids += 1
        elif val == 'Do' and stack and stack[-1][0] == 'name' and stack[-1][1] in names:
            s = form_summary(names[stack[-1][1]], depth + 1)
            if s[3] == 'Form':
                forms += 1; shows += s[0]; mcids += s[1]
        stack = []
    cache[obj] = (shows, mcids, forms, subtype)
    return cache[obj]

totals = collections.Counter()
for page in pages:
    res = show(f'pages/{page}/Resources', False)
    names = resources_xobjects(res)
    data = show(f'pages/{page}/Contents')
    marks, stack, row = [], [], collections.Counter()
    for kind, val in tokens(data):
        if kind != 'kw': stack.append((kind, val)); continue
        if val in ('BDC', 'BMC'):
            label = next((v for k, v in stack if k == 'name'), None)
            mcid = any(k == 'name' and v == 'MCID' for k, v in stack)
            parent = marks[-1] if marks else 'unmarked'
            marks.append('artifact' if label == 'Artifact' else ('mcid' if mcid else parent))
        elif val == 'EMC' and marks: marks.pop()
        elif val == 'Do' and stack and stack[-1][0] == 'name':
            obj = names.get(stack[-1][1])
            if obj:
                shows, mcids, forms, subtype = form_summary(obj)
                if subtype == 'Form':
                    context = marks[-1] if marks else 'unmarked'
                    content = 'text' if shows else ('mcid-only' if mcids else 'no-text')
                    row[f'{context}/{content}'] += 1
        stack = []
    totals.update(row)
    print(page, dict(row))
print('TOTAL', dict(totals))
