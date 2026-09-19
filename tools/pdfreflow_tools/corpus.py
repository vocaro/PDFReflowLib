"""The repository root, the pinned corpus, and byte-count plus SHA-256 file identities."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'Tests/PDFReflowLibTests/fixtures'


def manifest_cases(root=ROOT):
    """The registered corpus documents from corpus/manifest.json."""
    return json.loads((Path(root) / 'corpus/manifest.json').read_text())['documents']


def regression_contracts(root=ROOT):
    """The reviewed content contracts and exclusions from corpus/regressions.json."""
    return json.loads((Path(root) / 'corpus/regressions.json').read_text())


def find_case(cases, case_id):
    """The case with that ID, or None."""
    return next((case for case in cases if case['id'] == case_id), None)


def cached_source(case, root=ROOT):
    """Where the fetcher keeps the case's verified PDF."""
    return Path(root) / 'corpus/cache' / case['filename']


def digest(path):
    """The file's SHA-256 as lowercase hexadecimal, read in chunks."""
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def identity(path):
    """The file's byte count and SHA-256, as manifests record them."""
    path = Path(path)
    return {'bytes': path.stat().st_size, 'sha256': digest(path)}


def matches_identity(path, expected):
    """Whether the file has expected['bytes'] bytes and SHA-256 expected['sha256'].

    The byte count is compared first, so a file of the wrong size is never hashed.
    """
    path = Path(path)
    return path.stat().st_size == expected['bytes'] and digest(path) == expected['sha256']


def verify_source(path, case, label=None):
    """Return path once it has the case's pinned identity; raise ValueError naming the mismatch."""
    label = case['id'] if label is None else label
    path = Path(path)
    if path.stat().st_size != case['bytes']:
        raise ValueError(f'{label} source byte count mismatch')
    if digest(path) != case['sha256']:
        raise ValueError(f'{label} source checksum mismatch')
    return path
