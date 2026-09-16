"""Per-page numbered-block inventory of the algebra book: #39 before vs after, plus structural stats."""
import glob, html, re, zipfile
root = '/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad'
MARK = re.compile(r'^\s*(\d+)[.)]')

def pages_of(epub):
    z = zipfile.ZipFile(epub)
    names = sorted([n for n in z.namelist() if re.search(r'chapter-\d+\.xhtml$', n)], key=lambda n: int(re.search(r'chapter-(\d+)', n).group(1)))
    t = ''.join(z.read(n).decode() for n in names)
    page, pages = None, {}
    for m in re.finditer(r'id="page-(\d+)"|<(p|pre|h[1-6])(?: [^>]*)?>(.*?)</\2>', t, re.S):
        if m.group(1):
            page = int(m.group(1)); pages.setdefault(page, []); continue
        pages.setdefault(page, []).append((m.group(2), html.unescape(re.sub('<[^>]+>', '', m.group(3)))))
    return pages

before = pages_of(glob.glob(root + '/corpus-before/wallace-algebra-2010/*.epub')[0])
after = pages_of(glob.glob(root + '/corpus-after2/wallace-algebra-2010/*.epub')[0])
diff = []
for p in sorted(set(before) | set(after)):
    b = [(k, t) for k, t in before.get(p, []) if MARK.match(t)]
    a = [(k, t) for k, t in after.get(p, []) if MARK.match(t)]
    if b != a: diff.append((p, len(b), len(a)))
print('pages whose numbered blocks differ before/after #39:', diff)
# Structural inventory on the after book: numbered blocks that contain a second marker (merged entries)
merged = {}
for p, blocks in after.items():
    for k, t in blocks:
        if MARK.match(t) and len(re.findall(r'(?:^|\s)\d+\)\s*[−\-]?\s*\S', t)) >= 2 and k == 'p':
            merged.setdefault(p, []).append(t[:60])
print('pages with merged numbered paragraphs:', len(merged))
for p in sorted(merged)[:12]: print('  ', p, merged[p][:3])
print('answer-key pages (438-488) with merges:', [p for p in sorted(merged) if p >= 438])
