"""Compare cross-page paragraph joins between two corpus evaluations via read_pages."""
import sys
sys.path.insert(0, '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-ab246e000aa5e802d/tools')
from check_corpus_content import read_pages

LIMITS = dict(max_entries=20000, max_uncompressed_bytes=4 * 1024 ** 3)


def joins(path):
    pages, _ = read_pages(path, **LIMITS)
    out = {}
    numbers = sorted(pages)
    for n in numbers:
        nxt = pages.get(n + 1)
        if not nxt:
            continue
        for pid, text in pages[n].get('paragraphIDs', {}).items():
            if pid in nxt.get('paragraphIDs', {}):
                out[n] = (text[-70:], nxt['paragraphIDs'][pid][:70])
    return pages, out


def main(before, after, label):
    bp, bj = joins(before)
    ap, aj = joins(after)
    gained = sorted(set(aj) - set(bj))
    lost = sorted(set(bj) - set(aj))
    changed_text = [n for n in sorted(set(bp) & set(ap)) if ' '.join(bp[n]['text'].split()) != ' '.join(ap[n]['text'].split())]
    changed_images = [n for n in sorted(set(bp) & set(ap)) if len(bp[n]['images']) != len(ap[n]['images'])]
    print(f'=== {label}: joins before {len(bj)}, after {len(aj)}, gained {len(gained)}, lost {len(lost)}; pages with text changes {len(changed_text)}, image-count changes {len(changed_images)}')
    for n in gained:
        print(f'  + {n}->{n+1}  …{aj[n][0]!r} || {aj[n][1]!r}')
    for n in lost:
        print(f'  - {n}->{n+1}  …{bj[n][0]!r} || {bj[n][1]!r}')
    if '-v' in sys.argv:
        for n in changed_text:
            print(f'  ~ page {n} text changed')
        for n in changed_images:
            print(f'  ~ page {n} images {len(bp[n]["images"])} -> {len(ap[n]["images"])}')
    return changed_text


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3])
