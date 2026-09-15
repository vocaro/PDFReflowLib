#!/usr/bin/env python3
"""Explicitly fetch pinned development PDFs into an ignored cache; never run by Swift tests."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]


def valid_identity(path, case):
    if path.is_symlink():
        raise ValueError(f"Cache entry is a symlink: {path}")
    if not path.is_file() or path.stat().st_size != case['bytes']:
        return False
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest() == case['sha256']


def validate_case(case):
    name = case['filename']
    if (not isinstance(name, str) or not name.lower().endswith('.pdf')
            or name != Path(name).name or any(c in name for c in '/\\:')
            or name in {'.', '..'}):
        raise ValueError('Corpus filename must be a plain PDF filename')
    if not isinstance(case['bytes'], int) or not 0 < case['bytes'] <= 256 * 1024 * 1024:
        raise ValueError('Corpus byte count must be within the converter input ceiling')
    if not re.fullmatch(r'[0-9a-f]{64}', case['sha256']):
        raise ValueError('Corpus SHA-256 must be 64 lowercase hexadecimal digits')
    url = case.get('downloadURL')
    if url:
        parsed = urlsplit(url)
        if parsed.scheme not in {'https', 'http'} or not parsed.hostname or parsed.username or parsed.password:
            raise ValueError('Download URL must be HTTP(S), without embedded credentials')


def fetch_case(case, cache, *, refresh=False, timeout=60, opener=None):
    validate_case(case)
    if not math.isfinite(timeout) or timeout <= 0:
        raise ValueError('Timeout must be finite and positive')
    cache = Path(cache)
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / case['filename']
    valid = valid_identity(target, case)
    if valid and not refresh:
        return {'case': case['id'], 'status': 'cached', 'path': str(target.resolve()),
                'sha256': case['sha256']}
    url = case.get('downloadURL')
    if not url:
        raise ValueError(f"{case['id']} has no direct downloadURL; supply the pinned PDF in {cache}")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=cache, prefix='.' + case['filename'] + '.',
                                         suffix='.partial', delete=False) as output:
            temporary = Path(output.name)
            request = Request(url, headers={'User-Agent': 'PDFReflowLib-corpus/1', 'Accept-Encoding': 'identity'})
            total = 0
            digest = hashlib.sha256()
            with (opener or urlopen)(request, timeout=timeout) as response:
                while True:
                    chunk = response.read(min(1024 * 1024, case['bytes'] - total + 1))
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > case['bytes']:
                        raise ValueError('Download exceeds the pinned byte count; source may have changed')
                    output.write(chunk)
                    digest.update(chunk)
            if total != case['bytes'] or digest.hexdigest() != case['sha256']:
                raise ValueError('Downloaded PDF differs from pinned bytes/SHA-256; cache was not replaced')
        # Publish only verified bytes; a failed refresh leaves the old entry intact.
        if target.is_symlink():
            raise ValueError(f"Cache entry is a symlink: {target}")
        os.replace(temporary, target)
        return {'case': case['id'], 'status': 'downloaded', 'path': str(target.resolve()),
                'sha256': case['sha256']}
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument('--case', action='append', dest='cases', help='case ID; may be repeated')
    selection.add_argument('--all', action='store_true', help='fetch every registered case')
    parser.add_argument('--cache-dir', type=Path, default=ROOT / 'Corpus/cache')
    parser.add_argument('--refresh', action='store_true', help='refetch even when cached bytes match')
    parser.add_argument('--timeout', type=float, default=60, help='network operation timeout in seconds')
    args = parser.parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error('timeout must be finite and positive')
    cases = json.loads((ROOT / 'Corpus/manifest.json').read_text())['documents']
    if len({c['id'] for c in cases}) != len(cases) or len({c['filename'] for c in cases}) != len(cases):
        parser.error('duplicate corpus case ID or filename')
    selected = cases if args.all else [c for c in cases if c['id'] in args.cases]
    unknown = set(args.cases or []) - {c['id'] for c in cases}
    if unknown:
        parser.error('unknown cases: ' + ', '.join(sorted(unknown)))
    failed = False
    for case in selected:
        try:
            print(json.dumps(fetch_case(case, args.cache_dir, refresh=args.refresh, timeout=args.timeout)), flush=True)
        except (OSError, ValueError) as error:
            failed = True
            print(json.dumps({'case': case['id'], 'status': 'failed', 'error': str(error)}), file=sys.stderr, flush=True)
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
