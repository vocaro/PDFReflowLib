#!/usr/bin/env python3
"""Retain compact measurement evidence; large EPUBs remain in the explicit run directory."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    args.destination.mkdir(parents=True, exist_ok=False)
    for name in ('identity.json', 'comparison.json', 'results.json'):
        data = (args.source / name).read_bytes()
        target = args.destination / (name if name == 'identity.json' else name + '.gz')
        target.write_bytes(data if name == 'identity.json' else gzip.compress(data, mtime=0))
    manifest = []
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w') as archive:
        for path in sorted(args.source.rglob('*')):
            if not path.is_file() or path.suffix not in ('.json', '.log'): continue
            data = path.read_bytes(); relative = str(path.relative_to(args.source))
            info = tarfile.TarInfo(relative); info.size = len(data); info.mtime = 0
            archive.addfile(info, io.BytesIO(data))
            manifest.append({'path': relative, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    (args.destination / 'receipts.tar.gz').write_bytes(gzip.compress(buffer.getvalue(), mtime=0))
    (args.destination / 'receipts.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__': main()
