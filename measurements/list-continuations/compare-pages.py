"""Compare two corpus runs page by page: text, paragraph/pre block lists and image bytes."""
import hashlib
import json
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
import check_corpus_content as checker  # noqa: E402


def load(path):
    pages, _ = checker.read_pages(Path(path))
    with zipfile.ZipFile(path) as archive:
        digests = {name: hashlib.sha256(archive.read(name)).hexdigest()
                   for name in archive.namelist() if '/images/' in name}
    return pages, digests


def main():
    baseline, candidate, label = sys.argv[1], sys.argv[2], sys.argv[3]
    before, before_images = load(baseline)
    after, after_images = load(candidate)
    report = {
        'case': label,
        'pagesBefore': len(before), 'pagesAfter': len(after),
        'imagesBefore': len(before_images), 'imagesAfter': len(after_images),
        'imagesIdentical': before_images == after_images,
        'preBefore': sum(len(p['listItems']) for p in before.values()),
        'preAfter': sum(len(p['listItems']) for p in after.values()),
        'textChangedPages': [], 'blocksChangedPages': [],
    }
    for number in sorted(set(before) | set(after)):
        a, b = before.get(number, {}), after.get(number, {})
        if a.get('text') != b.get('text'):
            report['textChangedPages'].append(number)
        if a.get('paragraphs') != b.get('paragraphs') or a.get('listItems') != b.get('listItems'):
            report['blocksChangedPages'].append(number)
    print(json.dumps(report, indent=1))
    detail = Path(sys.argv[4]) if len(sys.argv) > 4 else None
    if detail:
        with detail.open('w') as handle:
            for number in report['blocksChangedPages']:
                a, b = before.get(number, {}), after.get(number, {})
                handle.write(f"===== {label} page {number}\n")
                for key in ('paragraphs', 'listItems'):
                    old, new = a.get(key, []), b.get(key, [])
                    for text in old:
                        if text not in new:
                            handle.write(f"  - {key[:3]}: {text}\n")
                    for text in new:
                        if text not in old:
                            handle.write(f"  + {key[:3]}: {text}\n")
                if a.get('text') != b.get('text'):
                    handle.write("  ! page text differs\n")


main()
