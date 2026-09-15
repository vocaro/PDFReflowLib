"""Retain issue #10 qualification and enforce the reviewed full-corpus change boundary."""
import argparse
import copy
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from check_corpus_content import check_evaluation, read_pages
from compare_conversion_runs import compare, image_hashes

CHANGED = {486: '468 NOTES TO CHAPTER 2', 488: '470 NOTES TO CHAPTER 2',
           574: '556 NOTES TO CHAPTER 10', 576: '558 NOTES TO CHAPTER 10',
           581: 'NOTES TO CHAPTER 12 563', 582: '564 NOTES TO CHAPTER 12',
           583: 'NOTES TO CHAPTER 12 565'}


def score(pages, annotations):
    expected = annotations['logicalHeadings']
    emitted = [(n, h) for n in range(19, 65) for h in pages[n]['headings']]
    true = [(n, h) for n, h in emitted if any(n == e['page'] and h in e['sourceLines'] for e in expected)]
    recovered = [e for e in expected if all((e['page'], line) in emitted for line in e['sourceLines'])]
    return {'physicalPages': [19, 64], 'emittedHeadingElements': len(emitted),
            'elementsMatchingSourceHeadingLines': len(true), 'falsePositiveElements': len(emitted) - len(true),
            'logicalMajorHeadings': len(expected), 'majorHeadingsWithAllLinesDetected': len(recovered),
            'singleElementMajorHeadings': sum((e['page'], e['text']) in emitted for e in expected),
            'missingMajorHeadings': [e for e in expected if e not in recovered],
            'emitted': [{'page': n, 'text': h} for n, h in emitted]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    def save(name, value):
        data = (json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode()
        (args.output / name).write_bytes(gzip.compress(data, mtime=0) if name.endswith('.gz') else data)
    cases = {c['id']: c for c in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']}
    contracts = json.loads((ROOT / 'corpus/regressions.json').read_text())['cases']
    comparisons, assessments, baseline_assessments = [], [], []
    for contract in contracts:
        name = contract['id']
        before, after = [args.run / phase / name for phase in ('baseline', 'candidate')]
        result = compare(before, after)
        assert not result.get('provenanceErrors') and not result.get('inspectionError'), result
        left, lm = read_pages(before / (name + '.epub'))
        right, rm = read_pages(after / (name + '.epub'))
        assert lm == rm and image_hashes(before / (name + '.epub')) == image_hashes(after / (name + '.epub'))
        reviewed = CHANGED if name == 'gpo-911-2004' else {50: '46 Promoting Financial System Stability'} if name == 'fed-explained-2021' else {}
        if reviewed:
            assert result['changedPages'] == sorted(reviewed), result
            for n, header in reviewed.items():
                assert left[n]['text'].startswith(header)
                assert left[n]['text'][len(header):].strip() == right[n]['text'], n
                assert [h for h in left[n]['headings'] if h != header] == right[n]['headings'], n
                assert [p for p in left[n]['paragraphs'] if p != header] == right[n]['paragraphs'], n
                assert left[n]['images'] == right[n]['images'], n
                assert [(s['tag'], s['text']) for s in left[n]['scripts']] == [(s['tag'], s['text']) for s in right[n]['scripts']], n
            assert set(result['changedReportFields']) <= {'warnings', 'reflowedPageCount'}, result
            reports = [json.loads((directory / 'conversion-report.json').read_text()) for directory in (before, after)]
            assert all(w in reports[1]['warnings'] for w in reports[0]['warnings'])
            added = [w for w in reports[1]['warnings'] if w not in reports[0]['warnings']]
            assert sorted(w['page'] for w in added) == sorted(reviewed)
            assert all(w['code'] == 'furnitureRemoved' for w in added)
            save(name + '-reviewed-changes.json.gz', {n: {'before': left[n], 'after': right[n]} for n in reviewed})
        else:
            assert result['passed'], result
        if name == 'gpo-911-2004':
            annotations = json.loads((Path(__file__).parent / 'annotations.json').read_text())
            metric = score(right, annotations)
            # Test the audit against false-positive and lost-title mutations.
            corrupt = copy.deepcopy(right)
            corrupt[33]['headings'].append('BOST')
            assert score(corrupt, annotations)['falsePositiveElements'] == metric['falsePositiveElements'] + 1
            corrupt = copy.deepcopy(right)
            corrupt[19]['headings'].remove('“WE HAVE')
            assert score(corrupt, annotations)['majorHeadingsWithAllLinesDetected'] == metric['majorHeadingsWithAllLinesDetected'] - 1
            metric['negativeControlsPassed'] = True
            save('heading-audit.json', metric)
            save('reviewed-pages.json.gz', {n: {'before': left[n], 'after': right[n]} for n in sorted(set(CHANGED) | {19, 32, 33, 50, 51, 53})})
        assessment = check_evaluation(cases[name], contract, after)
        assert assessment['passed'], assessment
        assessments.append(assessment)
        baseline_assessments.append(check_evaluation(cases[name], contract, before))
        result['reviewedChangeBoundaryPassed'] = True
        comparisons.append(result)
        for phase, directory in [('baseline', before), ('candidate', after)]:
            target = args.output / phase / name
            target.mkdir(parents=True, exist_ok=True)
            for filename in ['result.json', 'conversion-report.json', 'environment-probe.json', 'epubcheck.log', 'memory-samples.json', 'progress.log']:
                (target / (filename + '.gz')).write_bytes(gzip.compress((directory / filename).read_bytes(), mtime=0))
    save('comparison-summary.json', comparisons)
    save('content-assessments.json', assessments)
    save('before-content.json', baseline_assessments)
    for name in ['margins.json', 'margins-after.json']:
        save(name + '.gz', json.loads((args.run / name).read_text()))
    for name in ['before-tests.log', 'focused-tests.log', 'final-focused-tests.log', 'fast-gate.log', 'final-swift-tests.log', 'ios-tests.log', 'structure-memory.log', 'content-checker-tests.log', 'baseline-corpus.log', 'candidate-corpus.log']:
        (args.output / (name + '.gz')).write_bytes(gzip.compress((args.run / name).read_bytes(), mtime=0))
    paths = [p for folder in ['Sources', 'Tests', 'tools'] for p in (ROOT / folder).rglob('*') if p.is_file() and p.suffix in ['.swift', '.py', '.json']]
    paths += [ROOT / 'corpus/regressions.json', Path(__file__), Path(__file__).with_name('annotations.json')]
    paths += list(Path(__file__).resolve().parent.glob('map-region-*.png'))
    save('identity.json', {'baseRevision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                           'fileSHA256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)},
                           'scope': 'Same-context before/after runs with per-case raster/Vision capability receipts; no physical-device qualification.'})


if __name__ == '__main__':
    main()
