import sys, hashlib
from pathlib import Path

# usage: anehash.py name... : per compiled program, the e5 hash and the model.anehash parts
for name in sys.argv[1:]:
    root = Path.home() / 'Library/Caches' / name / 'com.apple.e5rt.e5bundlecache'
    print('==', name)
    for bundle in sorted(root.glob('*/*/*.bundle')):
        key = bundle.parent.name[:8]
        e5 = next(bundle.rglob('*.e5'), None)
        ane = next(bundle.rglob('model.anehash'), None)
        parts = ane.read_text().strip().split('_') if ane else []
        print(key, 'e5', hashlib.sha256(e5.read_bytes()).hexdigest()[:12] if e5 else None,
              'mtime', int(e5.stat().st_mtime) if e5 else None,
              'ane', [p[:10] for p in parts])
