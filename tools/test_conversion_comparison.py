import copy
import json
from pathlib import Path
import re
import tempfile
import unittest
import zipfile

from compare_conversion_runs import compare, compatible_receipts
from pdfreflow_tools.corpus import digest

FIXTURE = Path(__file__).resolve().parent / 'fixtures' / 'conversion-comparison'
PAGEBREAK = re.compile(r'<span[^>]*epub:type="pagebreak"[^>]*id="page-(\d+)"[^>]*/>')
PARAGRAPH = re.compile(r'<p\b[^>]*>.*?</p>', re.S)
FIGURE = re.compile(r'<figure>.*?</figure>', re.S)


class ConversionComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.receipt = {
            'provenanceSchemaVersion': 1, 'runID': 'run-control', 'outputSHA256': 'a' * 64,
            'case': {'id': 'control', 'sha256': 'b' * 64, 'pages': 1},
            'executionContext': 'host-terminal', 'system': 'macOS', 'systemBuild': 'build',
            'machine': 'arm64', 'options': 'library defaults', 'runPassed': True,
            'converterSHA256': 'c' * 64,
            'conversionReport': {'pageCount': 1, 'recognizedPageCount': 1, 'warnings': []},
            'environmentProbeCapture': {'executableSHA256': 'd' * 64, 'resultSHA256': 'e' * 64, 'exitCode': 0},
            'environmentProbe': {'schemaVersion': 1, 'runID': 'run-control', 'system': 'macOS build',
                'probeSHA256': 'd' * 64, 'sourceSHA256': 'b' * 64, 'page': 1,
                'packedPixelSHA256': 'f' * 64, 'metalDevice': 'device', 'colorSpaceName': 'DeviceRGB',
                'colorSpaceICC_SHA256': 'unavailable', 'width': 10, 'height': 10, 'bitsPerPixel': 32,
                'rasterDPI': 180, 'ocr': {'status': 'succeeded', 'lines': ['control']}},
        }

    def evaluation(self, name, *, body='<p>Original text</p>', image=b'pixels', receipt=None):
        path = self.root / name
        path.mkdir()
        with zipfile.ZipFile(path / 'control.epub', 'w') as archive:
            archive.writestr('EPUB/package.opf', '<package xmlns="http://www.idpf.org/2007/opf">'
                '<manifest><item id="c" href="chapter.xhtml"/></manifest>'
                '<spine><itemref idref="c"/></spine></package>')
            archive.writestr('EPUB/chapter.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml" '
                'xmlns:epub="http://www.idpf.org/2007/ops"><body>'
                '<span epub:type="pagebreak" id="page-1"/>' + body +
                '<img src="images/image-1.png"/></body></html>')
            archive.writestr('EPUB/images/image-1.png', image)
            archive.comment = name.encode()  # ZIP identity is deliberately irrelevant.
        receipt = copy.deepcopy(receipt or self.receipt)
        (path / 'environment-probe.json').write_text(json.dumps(receipt['environmentProbe']))
        (path / 'conversion-report.json').write_text(json.dumps(receipt['conversionReport']))
        receipt['outputSHA256'] = digest(path / 'control.epub')
        receipt['environmentProbeCapture']['resultSHA256'] = digest(path / 'environment-probe.json')
        (path / 'result.json').write_text(json.dumps(receipt))
        return path

    def test_same_context_different_binaries_and_zip_metadata_pass(self):
        candidate = copy.deepcopy(self.receipt)
        candidate['converterSHA256'] = '1' * 64
        candidate['conversionReport']['outputURL'] = 'different path'
        result = compare(self.evaluation('left'), self.evaluation('right', receipt=candidate))
        self.assertTrue(result['passed'])

    def test_missing_or_incompatible_environment_provenance_refuses_comparison(self):
        for field in ['system', 'systemBuild', 'machine', 'options']:
            for replacement in [None, 'other']:
                candidate = copy.deepcopy(self.receipt)
                candidate[field] = replacement
                self.assertTrue(compatible_receipts(self.receipt, candidate), (field, replacement))
        unknown = dict(self.receipt)
        unknown.pop('provenanceSchemaVersion')
        result = compare(self.evaluation('left'), self.evaluation('right', receipt=unknown))
        self.assertFalse(result['passed'])
        self.assertNotIn('changedImages', result)

    def test_context_labels_are_supplemental(self):
        left = self.evaluation('left')
        for name, label in [('different', 'sandbox'), ('missing', None)]:
            candidate = dict(self.receipt, executionContext=label)
            self.assertTrue(compare(left, self.evaluation(name, receipt=candidate))['passed'])

    def test_probe_must_be_bound_to_this_run_source_and_executable(self):
        for field, value in [('runID', 'stale-run'), ('sourceSHA256', '0' * 64),
                             ('probeSHA256', '0' * 64), ('page', 2), ('schemaVersion', 2)]:
            candidate = copy.deepcopy(self.receipt)
            candidate['environmentProbe'][field] = value
            self.assertTrue(compatible_receipts(self.receipt, candidate), field)

    def test_missing_or_malformed_probe_refuses_comparison(self):
        for value in [None, {}, [], 'invalid']:
            candidate = dict(self.receipt, environmentProbe=value)
            self.assertTrue(compatible_receipts(self.receipt, candidate))
        for field in ['environmentProbeCapture', 'outputSHA256', 'converterSHA256']:
            candidate = copy.deepcopy(self.receipt)
            del candidate[field]
            self.assertTrue(compatible_receipts(self.receipt, candidate), field)

    def test_matching_but_incomplete_capability_receipts_are_refused(self):
        for field in self.receipt['environmentProbe']:
            candidate = copy.deepcopy(self.receipt)
            del candidate['environmentProbe'][field]
            self.assertTrue(compatible_receipts(candidate, candidate), field)

    def test_nan_dimensions_and_malformed_ocr_are_refused(self):
        for field, value in [('width', float('nan')), ('height', -1), ('rasterDPI', float('inf')),
                             ('ocr', {'status': 'succeeded'}), ('ocr', {'status': 'succeeded', 'lines': [1]})]:
            candidate = copy.deepcopy(self.receipt)
            candidate['environmentProbe'][field] = value
            self.assertTrue(compatible_receipts(candidate, candidate), (field, value))

    def test_changed_artifacts_are_refused_before_content_comparison(self):
        left = self.evaluation('left')
        for index, filename in enumerate(['control.epub', 'environment-probe.json', 'conversion-report.json']):
            right = self.evaluation('right' + str(index))
            with (right / filename).open('ab') as stream:
                stream.write(b' ' if filename.endswith('.json') else b'changed')
            if filename == 'conversion-report.json':
                (right / filename).write_text('{}')
            result = compare(left, right)
            self.assertFalse(result['passed'], filename)
            self.assertTrue(result['provenanceErrors'])
            self.assertNotIn('changedPages', result)

    def test_missing_artifact_is_a_failed_result(self):
        left, right = self.evaluation('left'), self.evaluation('right')
        (right / 'environment-probe.json').unlink()
        self.assertTrue(compare(left, right)['provenanceErrors'])

    def test_changed_source_and_failed_evaluation_are_not_comparable(self):
        for field in ['id', 'sha256', 'pages']:
            candidate = copy.deepcopy(self.receipt)
            candidate['case'][field] = 'other'
            self.assertTrue(compatible_receipts(self.receipt, candidate))
        candidate = dict(self.receipt, runPassed=False)
        self.assertTrue(compatible_receipts(self.receipt, candidate))

    def test_same_binary_opposite_capabilities_refuse_even_with_matching_context_label(self):
        candidate = copy.deepcopy(self.receipt)
        candidate['environmentProbe'].update(metalDevice='unavailable', packedPixelSHA256='other',
            ocr={'status': 'failed', 'description': 'Failed to create CVPixelBuffer'})
        result = compare(self.evaluation('left'), self.evaluation('right', receipt=candidate))
        self.assertFalse(result['passed'])
        self.assertIn('capability probe metalDevice differs', result['provenanceErrors'])
        self.assertIn('capability probe packedPixelSHA256 differs', result['provenanceErrors'])
        self.assertIn('candidate raster/Vision capability probe missing or failed', result['provenanceErrors'])

    def test_pixel_asset_change_fails_even_when_parsed_text_agrees(self):
        result = compare(self.evaluation('left'), self.evaluation('right', image=b'changed pixels'))
        self.assertFalse(result['passed'])
        # A page now carries its images by their bytes rather than by their generated names (#92),
        # so re-encoding an asset names the page it sits on instead of only the asset.
        self.assertEqual(result['changedPages'], [1])
        self.assertEqual(result['changedPageFields']['1'], ['images'])
        self.assertEqual(result['changedImages'], ['EPUB/images/image-1.png'])

    def test_text_or_heading_change_fails_even_with_identical_images(self):
        left = self.evaluation('left')
        for name, body in [('text', '<p>Changed text</p>'), ('heading', '<h2>Original text</h2>')]:
            result = compare(left, self.evaluation(name, body=body))
            self.assertFalse(result['passed'])
            self.assertEqual(result['changedPages'], [1])
            self.assertEqual(result['changedImages'], [])

    def test_ocr_failure_is_visible_even_if_fallback_pixels_and_text_agree(self):
        candidate = copy.deepcopy(self.receipt)
        candidate['conversionReport'].update(recognizedPageCount=0,
            warnings=[{'code': 'ocrFailed', 'page': 1}])
        result = compare(self.evaluation('left'), self.evaluation('right', receipt=candidate))
        self.assertFalse(result['passed'])
        self.assertEqual(result['changedReportFields'], ['recognizedPageCount', 'warnings'])

    def test_added_null_report_field_is_still_a_difference(self):
        candidate = copy.deepcopy(self.receipt)
        candidate['conversionReport']['newField'] = None
        result = compare(self.evaluation('left'), self.evaluation('right', receipt=candidate))
        self.assertFalse(result['passed'])
        self.assertEqual(result['changedReportFields'], ['newField'])

    # A difference between two binaries is the change's doing only where one binary does not
    # produce it on its own. Converting twice with one binary is not a no-op: Vision's reading
    # of a page differs from run to run on the same host, and two corpus books lose whole
    # paragraphs of body prose to it (#284). `--control` is a second evaluation of the
    # baseline's own converter, and what it moves is not the candidate's.

    def test_a_difference_the_baselines_own_binary_also_makes_is_not_the_candidates(self):
        left = self.evaluation('left')
        control = self.evaluation('control-run', body='<p>Recognized differently</p>')
        candidate = copy.deepcopy(self.receipt)
        candidate['converterSHA256'] = '1' * 64
        right = self.evaluation('right', body='<p>Recognized differently</p>', receipt=candidate)
        result = compare(left, right, control=control)
        # The page differs between the two binaries, and it differs between two runs of one.
        self.assertEqual(result['changedPages'], [1])
        self.assertEqual(result['unstablePages'], [1])
        self.assertEqual(result['attributedPages'], [])
        self.assertTrue(result['passed'])
        self.assertEqual(result['controlConverterSHA256'], 'c' * 64)

    def test_a_difference_only_the_candidate_makes_is_still_attributed_to_it(self):
        left = self.evaluation('left')
        control = self.evaluation('control-run')
        candidate = copy.deepcopy(self.receipt)
        candidate['converterSHA256'] = '1' * 64
        right = self.evaluation('right', body='<p>Changed text</p>', receipt=candidate)
        result = compare(left, right, control=control)
        self.assertEqual(result['attributedPages'], [1])
        self.assertEqual(result['unstablePages'], [])
        self.assertFalse(result['passed'])

    def test_unstable_images_and_report_fields_are_separated_the_same_way(self):
        left = self.evaluation('left')
        unstable = copy.deepcopy(self.receipt)
        unstable['conversionReport']['recognizedPageCount'] = 0
        control = self.evaluation('control-run', image=b'other pixels', receipt=unstable)
        candidate = copy.deepcopy(unstable)
        candidate['converterSHA256'] = '1' * 64
        right = self.evaluation('right', image=b'other pixels', receipt=candidate)
        result = compare(left, right, control=control)
        self.assertEqual(result['unstableImages'], ['EPUB/images/image-1.png'])
        self.assertEqual(result['attributedImages'], [])
        self.assertEqual(result['unstableReportFields'], ['recognizedPageCount'])
        self.assertEqual(result['attributedReportFields'], [])
        self.assertTrue(result['passed'])

    def test_a_control_built_from_another_binary_is_refused(self):
        other = copy.deepcopy(self.receipt)
        other['converterSHA256'] = '2' * 64
        result = compare(self.evaluation('left'), self.evaluation('right'),
                         control=self.evaluation('control-run', receipt=other))
        self.assertFalse(result['passed'])
        self.assertIn('control converterSHA256 differs from baseline; '
                      'a control run must use the baseline converter', result['provenanceErrors'])
        self.assertNotIn('changedPages', result)

    def test_an_incomparable_control_refuses_the_comparison(self):
        other = copy.deepcopy(self.receipt)
        other['machine'] = 'x86_64'
        result = compare(self.evaluation('left'), self.evaluation('right'),
                         control=self.evaluation('control-run', receipt=other))
        self.assertFalse(result['passed'])
        self.assertIn('control machine differs', result['provenanceErrors'])

    def test_without_a_control_nothing_is_attributed_and_the_verdict_is_unchanged(self):
        left = self.evaluation('left')
        result = compare(left, self.evaluation('right', body='<p>Changed text</p>'))
        self.assertFalse(result['passed'])
        for key in ('unstablePages', 'attributedPages', 'controlConverterSHA256'):
            self.assertNotIn(key, result)
        self.assertTrue(compare(left, self.evaluation('same'))['passed'])

def page_bounds(chapter, number):
    """Where one source page's markup starts and the next page's marker begins."""
    markers = list(PAGEBREAK.finditer(chapter))
    index = [int(marker.group(1)) for marker in markers].index(number)
    end = markers[index + 1].start() if index + 1 < len(markers) else len(chapter)
    return markers[index].start(), end


def drop_paragraph(chapter, number):
    """Remove one whole paragraph from the middle of a source page, as an edit to that page would."""
    start, end = page_bounds(chapter, number)
    segment = chapter[start:end]
    paragraphs = list(PARAGRAPH.finditer(segment))
    chosen = paragraphs[len(paragraphs) // 2]
    return chapter[:start] + segment[:chosen.start()] + segment[chosen.end():] + chapter[end:]


def join_across_break(chapter, number):
    """Make the paragraph before a page marker and the one after it one straddling paragraph.

    Every page of this book but the first ends with the reference-image figure for the page,
    which is moved ahead of the joined paragraph so that it stays on the same page and keeps its
    place in that page's image list. Both pages then hold exactly the text and images they held;
    the only difference is that one block now spans the marker, which is what the book-wide
    paragraph ordinal used to be the only record of.
    """
    start, _ = page_bounds(chapter, number)
    marker = PAGEBREAK.match(chapter, start)
    before = list(PARAGRAPH.finditer(chapter, 0, start))[-1]
    after = PARAGRAPH.search(chapter, marker.end())
    between = chapter[before.end():start].strip()
    opening = before.group(0)[:before.group(0).index('>') + 1]
    left = before.group(0)[len(opening):-len('</p>')]
    right = after.group(0)[after.group(0).index('>') + 1:-len('</p>')]
    return (chapter[:before.start()] + between + '\n' + opening + left + marker.group(0)
            + right + '</p>' + chapter[after.end():])


def drop_image(chapter, assets, name):
    """Remove one image asset and renumber the rest, as a conversion that stopped emitting it would."""
    figure = next(match for match in FIGURE.finditer(chapter) if name.rpartition('/')[2] in match.group(0))
    chapter = chapter[:figure.start()] + chapter[figure.end():]
    renumbered, shift = {}, False
    for asset, sha256 in assets.items():
        if asset == name:
            shift = True
            continue
        number = int(asset[len('EPUB/images/image-'):-len('.png')])
        moved = number - 1 if shift else number
        renumbered['EPUB/images/image-%d.png' % moved] = sha256
        chapter = chapter.replace('src="images/image-%d.png"' % number,
                                  'src="images/image-%d.png"' % moved)
    return chapter, renumbered


class RealBookComparisonTests(unittest.TestCase):
    """#92, against the structure a real conversion produces.

    `tools/fixtures/conversion-comparison` is the census-rrs2002-01 EPUB as the converter wrote
    it (see its provenance.json): 20 source pages, 225 paragraphs numbered book-wide and 47
    image assets named `images/image-N.png` in book-wide order. Both numberings shift when an
    earlier page changes, which is what made the tool report every later page as changed.
    """

    report = {'pageCount': 20, 'recognizedPageCount': 20, 'warnings': []}

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.chapter = (FIXTURE / 'EPUB' / 'chapter-1.xhtml').read_text()
        self.assets = json.loads((FIXTURE / 'images.json').read_text())

    def book(self, name, *, chapter=None, assets=None):
        directory = self.root / name
        directory.mkdir()
        with zipfile.ZipFile(directory / 'census-rrs2002-01.epub', 'w') as archive:
            for relative in ('mimetype', 'META-INF/container.xml', 'EPUB/package.opf',
                             'EPUB/nav.xhtml', 'EPUB/style.css'):
                archive.writestr(relative, (FIXTURE / relative).read_bytes())
            archive.writestr('EPUB/chapter-1.xhtml', chapter if chapter is not None else self.chapter)
            for asset, sha256 in (self.assets if assets is None else assets).items():
                archive.writestr(asset, sha256)  # The real payload's digest stands in for its bytes.
            archive.comment = name.encode()
        probe = {'schemaVersion': 1, 'runID': 'run-census', 'system': 'macOS build',
                 'probeSHA256': 'd' * 64, 'sourceSHA256': 'b' * 64, 'page': 1,
                 'packedPixelSHA256': 'f' * 64, 'metalDevice': 'device', 'colorSpaceName': 'DeviceRGB',
                 'colorSpaceICC_SHA256': 'unavailable', 'width': 10, 'height': 10, 'bitsPerPixel': 32,
                 'rasterDPI': 180, 'ocr': {'status': 'succeeded', 'lines': ['control']}}
        (directory / 'environment-probe.json').write_text(json.dumps(probe))
        (directory / 'conversion-report.json').write_text(json.dumps(self.report))
        (directory / 'result.json').write_text(json.dumps({
            'provenanceSchemaVersion': 1, 'runID': 'run-census', 'environmentProbe': probe,
            'case': {'id': 'census-rrs2002-01', 'sha256': 'b' * 64, 'pages': 20},
            'executionContext': 'host-terminal', 'system': 'macOS', 'systemBuild': 'build',
            'machine': 'arm64', 'options': 'library defaults', 'runPassed': True,
            'converterSHA256': 'c' * 64, 'conversionReport': self.report,
            'environmentProbeCapture': {'executableSHA256': 'd' * 64, 'exitCode': 0,
                                        'resultSHA256': digest(directory / 'environment-probe.json')},
            'outputSHA256': digest(directory / 'census-rrs2002-01.epub')}))
        return directory

    def test_the_fixture_still_has_the_book_wide_numbering_this_pins(self):
        self.assertEqual(len(PAGEBREAK.findall(self.chapter)), 20)
        self.assertEqual(len(PARAGRAPH.findall(self.chapter)), 225)
        self.assertEqual(list(self.assets)[:2], ['EPUB/images/image-1.png', 'EPUB/images/image-2.png'])
        self.assertEqual(len(self.assets), 47)

    def test_two_runs_of_the_same_book_report_nothing(self):
        result = compare(self.book('left'), self.book('right'))
        self.assertTrue(result['passed'], result)
        self.assertEqual(result['idOnlyShifts'], {'pageCount': 0, 'fields': {}})
        self.assertEqual(result['imageRenames'], {'count': 0})

    def test_removing_one_paragraph_reports_only_its_page(self):
        result = compare(self.book('left'), self.book('right', chapter=drop_paragraph(self.chapter, 5)))
        self.assertFalse(result['passed'])
        self.assertEqual(result['changedPages'], [5])
        self.assertEqual(result['changedPageFields']['5'], ['paragraphSpans', 'paragraphs', 'text'])
        self.assertEqual(result['changedImages'], [])
        # The 15 pages that used to be reported are now visible as what they are: renumbering.
        self.assertEqual(result['idOnlyShifts'], {'pageCount': 14, 'fields': {'paragraphIDs': 14}})

    def test_a_later_real_change_is_not_hidden_by_the_normalization(self):
        edited = drop_paragraph(self.chapter, 5).replace('disclosure', 'DISCLOSURE', 1)
        self.assertIn('DISCLOSURE', edited)
        result = compare(self.book('left'), self.book('right', chapter=edited))
        self.assertFalse(result['passed'])
        self.assertEqual(len(result['changedPages']), 2)
        self.assertEqual(result['changedPages'][0], 5)

    def test_a_paragraph_joined_across_a_page_break_is_still_a_change(self):
        joined = join_across_break(self.chapter, 6)
        result = compare(self.book('left'), self.book('right', chapter=joined))
        self.assertFalse(result['passed'])
        self.assertEqual(result['changedPages'], [5, 6])
        # Both pages keep their own text; only the block's continuity across the marker changed.
        for page in ('5', '6'):
            self.assertEqual(result['changedPageFields'][page], ['paragraphSpans'])

    def test_a_renumbered_image_asset_is_a_rename_and_only_its_own_page_changes(self):
        removed = 'EPUB/images/image-3.png'  # A preserved region on source page 4.
        chapter, assets = drop_image(self.chapter, self.assets, removed)
        result = compare(self.book('left'), self.book('right', chapter=chapter, assets=assets))
        self.assertFalse(result['passed'])
        self.assertEqual(result['changedImages'], [removed])
        self.assertEqual(result['changedPages'], [4])
        self.assertEqual(result['imageRenames']['count'], 44)

    def test_detail_names_the_shifted_pages_and_renamed_assets(self):
        result = compare(self.book('left'), self.book('right', chapter=drop_paragraph(self.chapter, 5)),
                         detail=True)
        self.assertEqual(sorted(int(page) for page in result['idOnlyShifts']['pages']),
                         [6, 7, 8, 9, 10, 11, 13, 14, 15, 16, 17, 18, 19, 20])
        self.assertEqual(result['imageRenames']['pairs'], [])
