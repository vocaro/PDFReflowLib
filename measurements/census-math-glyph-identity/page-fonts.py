"""Census page by page: the glyphs each font draws, the names they carry, and whether any name
states a character (#297).

    python3 measurements/census-math-glyph-identity/page-fonts.py corpus/cache/rrs2002-01.pdf

Needs `mutool` (MuPDF) on the PATH. `mutool trace` reports every glyph a page draws with its
font and the glyph name the font gives it: the `Differences` name for a Type 1 font, which for
this file is also the CFF charset name. For a Type 3 font it reports the character code, so the
name is read from that font's own `Differences` (`mutool show`), which is also its `CharProcs`
key. A name states a character when it is not index-style in
`TextEncodingCheck.isIndexStyleGlyphName`'s sense (a letter prefix of at most two letters, or
`glyph`/`index`/`cid`/`gid`, then decimal digits).

Prints one JSON object per page: the glyphs of the fonts `GlyphIndexDecoder` establishes, and
those of every other font, with `withoutIdentity` counting the glyphs of the fonts nothing in the
file identifies (no name that states a character, and no outline an established font shares; see
`glyph-outlines.py`, which finds such outlines for `cmr` alone). Then one object per font.
"""
import collections
import json
import re
import subprocess
import sys

source = sys.argv[1]
# The fonts GlyphIndexDecoder establishes from the document's own words (#143, #226): the Cork
# text fonts by the word gate, `dctt` by corroboration.
DECODED = {'dcr10084', 'dcbx100120', 'dcti10084', 'dctt10075'}
# The Word cover's TrueType fonts name their glyphs, and the page extracts cleanly.
NAMED = {'TimesNewRoman', 'TimesNewRoman,Bold', 'TimesNewRoman,Italic'}
# The one undecoded font whose glyphs share outlines with an established font (glyph-outlines.py).
SHARED_OUTLINES = {'cmr10084'}


def index_style(name):
    match = re.fullmatch(r'([A-Za-z]+)(\d+)', name)
    if not match:
        return False
    prefix = match.group(1).lower()
    if prefix in ('u', 'uni'):
        return False
    return len(prefix) <= 2 or prefix in ('glyph', 'index', 'cid', 'gid')


def family(font):
    return font.split('+')[-1]


def run(*arguments):
    return subprocess.run(['mutool', *arguments], capture_output=True, text=True, errors='replace').stdout


pages = int(re.search(r'Pages: (\d+)', run('info', source)).group(1))

# Each Type 3 font's own names, code by code.
type3_names = {}
size = int(re.search(r'/Size (\d+)', run('show', source, 'trailer')).group(1))
for number in range(1, size):
    body = run('show', source, str(number))
    if '/Subtype /Type3' not in body:
        continue
    name = re.search(r'/Name /(\S+)', body).group(1)
    encoding = re.search(r'/Encoding (\d+) 0 R', body)
    differences = run('show', source, encoding.group(1)) if encoding else body
    array = re.search(r'/Differences \[(.*?)\]', differences, re.S).group(1)
    code, names = 0, {}
    for token in re.findall(r'/?[^\s\[\]/]+', array):
        if token.startswith('/'):
            names[str(code)] = token[1:]
            code += 1
        else:
            code = int(token)
    bitmap = '/ImageB' in run('show', source, re.search(r'/Resources (\d+) 0 R', body).group(1)) \
        if re.search(r'/Resources (\d+) 0 R', body) else None
    type3_names[name] = {'names': names, 'bitmap': bitmap}

fonts = collections.defaultdict(lambda: {'glyphs': 0, 'names': set(), 'pages': set()})
for page in range(1, pages + 1):
    counts = collections.Counter()
    font = None
    for line in run('trace', source, str(page)).splitlines():
        span = re.search(r'<span font="([^"]+)"', line)
        if span:
            font = family(span.group(1))
            continue
        glyph = re.search(r'<g unicode="[^"]*" glyph="([^"]+)"', line)
        if glyph and font:
            name = type3_names[font]['names'].get(glyph.group(1), '?') if font in type3_names else glyph.group(1)
            counts[font] += 1
            fonts[font]['glyphs'] += 1
            fonts[font]['names'].add(name)
            fonts[font]['pages'].add(page)
    decoded = sum(n for f, n in counts.items() if f in DECODED)
    others = {f: n for f, n in sorted(counts.items()) if f not in DECODED}
    without = sum(n for f, n in others.items() if f not in NAMED and f not in SHARED_OUTLINES)
    print(json.dumps({'page': page, 'decodedGlyphs': decoded, 'otherGlyphs': others,
                      'withoutIdentity': without}))
for font, entry in sorted(fonts.items()):
    names = sorted(entry['names'], key=lambda n: (re.sub(r'\d', '', n), int(re.sub(r'\D', '', n) or 0)))
    stating = [n for n in names if not index_style(n)]
    print(json.dumps({'font': font, 'type3Bitmap': type3_names.get(font, {}).get('bitmap'),
                      'decoded': font in DECODED, 'glyphs': entry['glyphs'], 'distinctNames': len(names),
                      'namesStatingACharacter': len(stating), 'sample': names[:6],
                      'pages': sorted(entry['pages'])}))
