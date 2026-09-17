"""Survey every cached corpus PDF's annotations (#151).

    xcrun swiftc -O annotation-dictionaries.swift -o /tmp/annots
    xcrun swiftc -O annotation-rendering.swift -o /tmp/annot-render
    python3 survey.py [--render] [pdf ...]

`annotation-dictionaries.swift <pdf> [v]` prints each annotation's raw dictionary evidence:
subtype, field type, flags, border width and colour, appearance streams and field value.
`annotation-rendering.swift <pdf> [v]` prints, per page, how many pixels PDFKit's annotation
drawing changes against the same page drawn without annotations, at one pixel per point, and how
many of its own pixels each annotation inks drawn alone over transparency. Both read only; neither
uses the library, so they are independent evidence for what a page image would preserve.
"""
import glob
import os
import subprocess
import sys

CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'corpus', 'cache')
TOOL = '/tmp/annot-render' if '--render' in sys.argv else '/tmp/annots'
files = [a for a in sys.argv[1:] if not a.startswith('--')] or sorted(glob.glob(os.path.join(CACHE, '*.pdf')))
for path in files:
    print('==', os.path.basename(path))
    print(subprocess.run([TOOL, path], capture_output=True, text=True).stdout.strip())
