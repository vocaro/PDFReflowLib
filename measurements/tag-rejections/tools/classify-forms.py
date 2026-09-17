"""classify_forms.py <forms.txt> [image-backed pages]: group pages by what their Form XObjects hold."""
import ast, collections, sys
pages = {}
for line in open(sys.argv[1]):
    if line.startswith('TOTAL'): continue
    n, d = line.split(' ', 1); pages[int(n)] = ast.literal_eval(d)
cls = collections.defaultdict(list)
for n, d in pages.items():
    kinds = {k.split('/')[1] for k in d}
    ctx = sorted(k for k in d if not k.endswith('no-text'))
    cls['textless forms only' if kinds <= {'no-text'} else 'text form: ' + ','.join(ctx)].append(n)
for k, v in sorted(cls.items(), key=lambda kv: -len(kv[1])):
    print(f'{k}\t{len(v)}\t{v}')
if len(sys.argv) > 2:
    for n in map(int, sys.argv[2].split(',')):
        print('image-backed', n, pages.get(n))
