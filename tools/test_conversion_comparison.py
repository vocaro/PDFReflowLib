import copy
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from compare_conversion_runs import compare, compatible_receipts
from conversion_provenance import digest


class EvaluationFixture(unittest.TestCase):
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
            'visionModelCache': {'mode': 'fresh', 'after': {'executableName': 'pdf-reflow-1a2b3c4d',
                                                            'programsSHA256': '9' * 64}},
            'conversionReport': {'pageCount': 1, 'recognizedPageCount': 1, 'warnings': []},
            'environmentProbeCapture': {'executableSHA256': 'd' * 64, 'resultSHA256': 'e' * 64, 'exitCode': 0},
            'environmentProbe': {'schemaVersion': 1, 'runID': 'run-control', 'system': 'macOS build',
                'probeSHA256': 'd' * 64, 'sourceSHA256': 'b' * 64, 'page': 1,
                'packedPixelSHA256': 'f' * 64, 'metalDevice': 'device', 'colorSpaceName': 'DeviceRGB',
                'colorSpaceICC_SHA256': 'unavailable', 'width': 10, 'height': 10, 'bitsPerPixel': 32,
                'rasterDPI': 180, 'ocr': {'status': 'succeeded', 'lines': ['control']}},
        }

    def evaluation(self, name, *, body='<p>Original text</p>', image=b'pixels', receipt=None,
                   chapters=None, images=None, nav=None):
        """chapters: spine document bodies (named chapter-1.xhtml...); images: asset name -> bytes;
        nav: optional navigation document body."""
        path = self.root / name
        path.mkdir()
        if chapters is None:
            chapters = ['<span epub:type="pagebreak" id="page-1"/>' + body + '<img src="images/image-1.png"/>']
            images = {'image-1.png': image}
        head = ('<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
                '<head><title>Control</title></head><body>')
        with zipfile.ZipFile(path / 'control.epub', 'w') as archive:
            items = ''.join(f'<item id="c{index}" href="chapter-{index + 1}.xhtml"/>' for index in range(len(chapters)))
            if nav is not None:
                items += '<item id="nav" href="nav.xhtml" properties="nav"/>'
            spine = ''.join(f'<itemref idref="c{index}"/>' for index in range(len(chapters)))
            archive.writestr('EPUB/package.opf', '<package xmlns="http://www.idpf.org/2007/opf">'
                f'<manifest>{items}</manifest><spine>{spine}</spine></package>')
            for index, chapter in enumerate(chapters):
                archive.writestr(f'EPUB/chapter-{index + 1}.xhtml', head + chapter + '</body></html>')
            if nav is not None:
                archive.writestr('EPUB/nav.xhtml', head + nav + '</body></html>')
            for asset, data in (images or {}).items():
                archive.writestr('EPUB/images/' + asset, data)
            archive.comment = name.encode()  # ZIP identity is deliberately irrelevant.
        receipt = copy.deepcopy(receipt or self.receipt)
        (path / 'environment-probe.json').write_text(json.dumps(receipt['environmentProbe']))
        (path / 'conversion-report.json').write_text(json.dumps(receipt['conversionReport']))
        receipt['outputSHA256'] = digest(path / 'control.epub')
        receipt['environmentProbeCapture']['resultSHA256'] = digest(path / 'environment-probe.json')
        (path / 'result.json').write_text(json.dumps(receipt))
        return path


class ConversionComparisonTests(EvaluationFixture):
    def test_same_context_different_binaries_and_zip_metadata_pass_when_explicitly_allowed(self):
        candidate = copy.deepcopy(self.receipt)
        candidate['converterSHA256'] = '1' * 64
        candidate['conversionReport']['outputURL'] = 'different path'
        result = compare(self.evaluation('left'), self.evaluation('right', receipt=candidate),
                         allow_different_converters=True)
        self.assertTrue(result['passed'])
        self.assertFalse(result['sameConverter'])

    def test_different_converter_binaries_are_refused_by_default(self):
        candidate = copy.deepcopy(self.receipt)
        candidate['converterSHA256'] = '1' * 64
        result = compare(self.evaluation('left'), self.evaluation('right', receipt=candidate))
        self.assertFalse(result['passed'])
        self.assertNotIn('changedPages', result)
        [error] = result['provenanceErrors']
        self.assertIn('converterSHA256 differs', error)
        self.assertIn('--allow-different-converters', error)
        self.assertTrue(compare(self.evaluation('same-left'), self.evaluation('same-right'))['sameConverter'])

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

    def ocr_receipt(self, programs='9' * 64, mode='fresh'):
        receipt = copy.deepcopy(self.receipt)
        receipt['conversionReport']['warnings'] = [{'code': 'ocrUsed', 'page': 1, 'message': 'OCR'}]
        receipt['visionModelCache'] = {'mode': mode, 'after': {'executableName': 'pdf-reflow', 'programsSHA256': programs}}
        if programs is None:
            del receipt['visionModelCache']
        return receipt

    def test_changed_ocr_pages_carry_a_caveat_unless_vision_programs_match(self):
        """#94: OCR text can change with Vision's compiled programs alone; the change is flagged, not hidden."""
        left = self.evaluation('left', receipt=self.ocr_receipt())
        cases = [('differ', self.ocr_receipt('8' * 64, mode='inherited'), False, 'differ'),
                 ('unrecorded', self.ocr_receipt(None), None, 'were not recorded'),
                 ('same', self.ocr_receipt(), True, None)]
        for name, receipt, same, wording in cases:
            with self.subTest(programs=name):
                result = compare(left, self.evaluation(name, body='<p>Recognized differently</p>', receipt=receipt))
                self.assertEqual(result['provenanceErrors'], [])
                self.assertFalse(result['passed'])
                self.assertEqual(result['changedPages'], [1])
                self.assertEqual(result['changedOCRPages'], [1])
                self.assertIs(result['sameVisionPrograms'], same)
                if wording:
                    self.assertIn(f"compiled Vision programs {wording}", result['ocrCaveat'])
                    self.assertIn('#94', result['ocrCaveat'])
                else:
                    self.assertNotIn('ocrCaveat', result)
        self.assertEqual(result['visionModelCaches']['candidate'],
                         {'mode': 'fresh', 'executableName': 'pdf-reflow', 'programsSHA256': '9' * 64})

    def test_ocr_pages_that_lose_words_are_named_even_when_programs_differ(self):
        """#116: a compile that drops paragraphs is a text loss, which the #94 caveat must not hide."""
        paragraph = ' '.join(f'word{i}' for i in range(60))
        left = self.evaluation('left', body=f'<p>{paragraph}</p>', receipt=self.ocr_receipt())
        lossy = self.evaluation('lossy', body='<p>word1 word2 word3 word4 word5</p>',
                                receipt=self.ocr_receipt('8' * 64, mode='fresh'))
        result = compare(left, lossy)
        self.assertEqual(result['changedOCRPages'], [1])
        self.assertIn('ocrCaveat', result)
        self.assertEqual(result['ocrTextVolume'], {'pages': 1, 'baselineWords': 60, 'candidateWords': 5,
                                                   'pagesWithFewerWords': {'baseline': [], 'candidate': [1]}})
        self.assertIn('the candidate has under 80%', result['ocrTextLoss'])
        self.assertIn('#116', result['ocrTextLoss'])
        # Rewording by another compile keeps the volume and is not called a loss.
        reworded = self.evaluation('reworded', body=f'<p>{paragraph.replace("word1 ", "wrod1 ")}</p>',
                                   receipt=self.ocr_receipt('8' * 64, mode='fresh'))
        result = compare(left, reworded)
        self.assertEqual(result['changedOCRPages'], [1])
        self.assertNotIn('ocrTextLoss', result)
        self.assertEqual(result['ocrTextVolume']['pagesWithFewerWords'], {'baseline': [], 'candidate': []})
        # Small pages cannot trip the check: fewer than 25 words apart.
        short = self.evaluation('short-left', body='<p>' + ' '.join(['w'] * 20) + '</p>', receipt=self.ocr_receipt())
        result = compare(short, self.evaluation('short-right', body='<p>w</p>', receipt=self.ocr_receipt('8' * 64)))
        self.assertNotIn('ocrTextLoss', result)

    def test_changes_off_ocr_pages_carry_no_vision_caveat(self):
        candidate = self.ocr_receipt('8' * 64)
        candidate['conversionReport']['warnings'] = []
        baseline = self.ocr_receipt()
        baseline['conversionReport']['warnings'] = []
        result = compare(self.evaluation('left', receipt=baseline),
                         self.evaluation('right', body='<p>Changed layout</p>', receipt=candidate))
        self.assertEqual((result['changedPages'], result['changedOCRPages']), ([1], []))
        self.assertIs(result['sameVisionPrograms'], False)
        self.assertNotIn('ocrCaveat', result)
        # A page recognized in only one run is not an OCR page of both.
        candidate['conversionReport']['warnings'] = [{'code': 'ocrUsed', 'page': 1, 'message': 'OCR'}]
        result = compare(self.evaluation('left-2', receipt=baseline),
                         self.evaluation('right-2', body='<p>Changed layout</p>', receipt=candidate))
        self.assertEqual(result['changedOCRPages'], [])

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
        # The page shows other bytes, so the page itself changed as well as the asset.
        self.assertEqual(result['changedPages'], [1])
        self.assertEqual(result['changedPageFields'], {'1': ['images', 'markup']})
        self.assertEqual(result['changedImages'], ['EPUB/images/image-1.png'])
        self.assertEqual(result['imageRenames'], {'count': 0})

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


class GeneratedIdentifierTests(EvaluationFixture):
    """#92: generated identifiers that shift without a content change are summarized, not drift."""

    PAGES = {1: '<p>Alpha</p><p>Beta</p>', 2: '<p>Gamma</p>',
             3: '<h2 id="heading-3-0">Delta</h2><p>Epsilon</p>'}
    NOTE_PAGES = {
        1: '<p>Claim<sup><a epub:type="noteref" role="doc-noteref" id="noteref-c1-1" '
           'href="chapter-2.xhtml#note-c1-1">1</a></sup> made.</p>',
        2: '<h2 id="heading-2-0">Middle</h2>',
        3: '<div class="footnote" role="doc-footnote" id="note-c1-1"><p><a href="chapter-1.xhtml#noteref-c1-1" '
           'role="doc-backlink" epub:type="backlink">1</a> Source.</p></div>'
           '<div class="footnote" role="doc-footnote" id="note-c1-2"><p>2 Other.</p></div>'}
    NAV = ('<nav epub:type="toc" id="toc"><h1>Contents</h1><ol><li><a href="chapter-{0}.xhtml#heading-2-{1}">'
           '{2}</a></li></ol></nav><nav epub:type="page-list"><ol><li><a href="chapter-{0}.xhtml#page-2">2</a>'
           '</li></ol></nav>')

    def book(self, name, pages, *, split=(), images=None, nav=None, receipt=None):
        """pages: page number -> markup after its marker, in order; split: pages starting a spine document."""
        chapters, current = [], ''
        for number, markup in pages.items():
            if number in split and current:
                chapters.append(current)
                current = ''
            current += f'<span epub:type="pagebreak" id="page-{number}"/>' + markup
        chapters.append(current)
        return self.evaluation(name, chapters=chapters, images=images or {}, nav=nav, receipt=receipt)

    def test_identical_books_packed_differently_pass_without_shifts(self):
        same = compare(self.book('left', self.PAGES), self.book('same', self.PAGES))
        self.assertTrue(same['passed'])
        self.assertEqual(same['idOnlyShifts'], {'pageCount': 0, 'fields': {}, 'navigationEntries': 0})
        # Page 3's heading now lives in chapter-2.xhtml: its anchor key moves, its content does not.
        repacked = compare(self.book('left-2', self.PAGES), self.book('repacked', self.PAGES, split={2}))
        self.assertTrue(repacked['passed'])
        self.assertEqual(repacked['idOnlyShifts'], {'pageCount': 1, 'fields': {'anchors': 1}, 'navigationEntries': 0})

    def test_removed_paragraph_reports_only_its_page(self):
        candidate = (self.PAGES | {1: '<p>Alpha</p>'})
        result = compare(self.book('left', self.PAGES), self.book('right', candidate), detail=True)
        self.assertFalse(result['passed'])
        self.assertEqual(result['changedPages'], [1])
        self.assertEqual(result['changedPageFields']['1'], ['markup', 'paragraphIDs', 'paragraphs', 'text'])
        self.assertEqual(result['idOnlyShifts']['pageCount'], 2)
        self.assertEqual(result['idOnlyShifts']['fields'], {'paragraphIDs': 2})
        self.assertEqual(result['idOnlyShifts']['pages'], {'2': ['paragraphIDs'], '3': ['paragraphIDs']})

    def test_removed_paragraph_does_not_hide_a_later_real_change(self):
        candidate = (self.PAGES | {1: '<p>Alpha</p>', 3: '<h2 id="heading-3-0">Delta</h2><p>Epsilon!</p>'})
        result = compare(self.book('left', self.PAGES), self.book('right', candidate))
        self.assertEqual(result['changedPages'], [1, 3])
        self.assertEqual(result['idOnlyShifts']['pageCount'], 1)

    def test_heading_level_and_element_type_changes_are_reported(self):
        for name, markup in [('level', '<h3 id="heading-3-0">Delta</h3><p>Epsilon</p>'),
                             ('type', '<h2 id="heading-3-0">Delta</h2><pre>Epsilon</pre>')]:
            result = compare(self.book('left-' + name, self.PAGES),
                             self.book(name, (self.PAGES | {3: markup})))
            self.assertFalse(result['passed'], name)
            self.assertEqual(result['changedPages'], [3], name)

    def test_paragraph_split_at_a_page_marker_is_reported_on_both_pages(self):
        left = self.evaluation('left', chapters=['<span epub:type="pagebreak" id="page-1"/><p>Lead</p>'
            '<p>Start <span epub:type="pagebreak" id="page-2"/>end.</p><p>Next</p>'], images={})
        right = self.evaluation('right', chapters=['<span epub:type="pagebreak" id="page-1"/><p>Lead</p>'
            '<p>Start</p><span epub:type="pagebreak" id="page-2"/><p>end.</p><p>Next</p>'], images={})
        result = compare(left, right)
        self.assertEqual(result['changedPages'], [1, 2])
        self.assertEqual(result['changedPageFields'], {'1': ['markup', 'paragraphIDs'],
                                                       '2': ['markup', 'paragraphIDs']})

    def test_added_image_renames_later_assets_without_changing_their_pages(self):
        pages = {1: '<p>One</p>', 2: '<img src="images/image-1.png"/>', 3: '<img src="images/image-2.png"/>'}
        left = self.book('left', pages, images={'image-1.png': b'A', 'image-2.png': b'B'})
        right = self.book('right', {1: '<p>One</p><img src="images/image-1.png"/>',
                                    2: '<img src="images/image-2.png"/>', 3: '<img src="images/image-3.png"/>'},
                          images={'image-1.png': b'C', 'image-2.png': b'A', 'image-3.png': b'B'})
        result = compare(left, right, detail=True)
        self.assertFalse(result['passed'])
        self.assertEqual(result['changedPages'], [1])
        self.assertEqual(result['changedImages'], ['EPUB/images/image-1.png'])
        self.assertEqual(result['imageRenames'], {'count': 2, 'pairs': [
            ['EPUB/images/image-1.png', 'EPUB/images/image-2.png'],
            ['EPUB/images/image-2.png', 'EPUB/images/image-3.png']]})
        self.assertEqual(result['idOnlyShifts']['pages'], {'2': ['images', 'markup'], '3': ['images', 'markup']})

    def test_renamed_source_page_reference_is_an_id_only_shift(self):
        """#132: removing an earlier image renames a page's `Original page N` reference, not its bytes."""
        reference = '<p>Text</p><img src="images/image-{}.png" alt="Original page 2"/>'
        left = self.book('left', {1: '<img src="images/image-1.png"/>', 2: reference.format(2)},
                         images={'image-1.png': b'A', 'image-2.png': b'B'})
        right = self.book('right', {1: '', 2: reference.format(1)}, images={'image-1.png': b'B'})
        result = compare(left, right, detail=True)
        self.assertEqual(result['changedPages'], [1])
        self.assertEqual(result['idOnlyShifts']['pages'], {'2': ['images', 'markup', 'pageReferences']})
        changed = self.book('changed', {1: '', 2: reference.format(1)}, images={'image-1.png': b'C'})
        self.assertEqual(compare(left, changed)['changedPageFields']['2'], ['images', 'markup', 'pageReferences'])

    def test_moved_or_swapped_images_are_reported(self):
        images = {'image-1.png': b'A', 'image-2.png': b'B'}
        left = self.book('left', {1: '<img src="images/image-1.png"/>', 2: '<img src="images/image-2.png"/>'},
                         images=images)
        moved = self.book('moved', {1: '<p>x</p>',
                                    2: '<img src="images/image-1.png"/><img src="images/image-2.png"/>'},
                          images=images)
        swapped = self.book('swapped', {1: '<img src="images/image-1.png"/>', 2: '<img src="images/image-2.png"/>'},
                            images={'image-1.png': b'B', 'image-2.png': b'A'})
        for candidate in (moved, swapped):
            result = compare(left, candidate)
            self.assertFalse(result['passed'])
            self.assertEqual(result['changedPages'], [1, 2])
            self.assertEqual(result['changedImages'], [])

    def test_spine_file_names_and_note_ids_resolve_to_the_same_targets(self):
        left = self.book('left', self.NOTE_PAGES, split={3}, nav=self.NAV.format(1, 0, 'Middle'))
        # Every page in its own document, note scope renumbered and the heading index changed.
        pages = {number: markup.replace('chapter-2.xhtml', 'chapter-3.xhtml').replace('c1-', 'c2-')
                 for number, markup in self.NOTE_PAGES.items()}
        pages[2] = '<h2 id="heading-2-1">Middle</h2>'
        right = self.book('right', pages, split={2, 3}, nav=self.NAV.format(2, 1, 'Middle'))
        result = compare(left, right, detail=True)
        self.assertTrue(result['passed'], result)
        self.assertEqual(result['idOnlyShifts']['pages'],
                         {'1': ['anchors', 'markup', 'noterefs'], '2': ['anchors', 'markup'],
                          '3': ['anchors', 'markup']})
        self.assertEqual(result['idOnlyShifts']['navigationEntries'], 1)

    def test_retargeted_note_link_and_changed_navigation_are_reported(self):
        left = self.book('left', self.NOTE_PAGES, split={3}, nav=self.NAV.format(1, 0, 'Middle'))
        # Same masked id and target page, so only the resolved target text tells the notes apart.
        retargeted = self.book('retargeted', (self.NOTE_PAGES | {
            1: self.NOTE_PAGES[1].replace('#note-c1-1', '#note-c1-2')}), split={3}, nav=self.NAV.format(1, 0, 'Middle'))
        result = compare(left, retargeted)
        self.assertFalse(result['passed'])
        self.assertEqual(result['changedPages'], [1])
        self.assertEqual(result['changedPageFields'], {'1': ['noterefs']})
        renamed = self.book('renamed', self.NOTE_PAGES, split={3}, nav=self.NAV.format(1, 0, 'Centre'))
        result = compare(left, renamed)
        self.assertFalse(result['passed'])
        self.assertEqual(result['changedPages'], [])
        self.assertTrue(result['navigationChanged'])
        self.assertEqual(result['changedNavigationPages'], [2])

    def test_page_warning_change_is_reported_on_its_page(self):
        receipt = copy.deepcopy(self.receipt)
        receipt['conversionReport']['warnings'] = [{'code': 'furnitureRemoved', 'message': 'm', 'page': 2}]
        result = compare(self.book('left', self.PAGES, receipt=receipt), self.book('right', self.PAGES))
        self.assertFalse(result['passed'])
        self.assertEqual(result['changedPages'], [2])
        self.assertEqual(result['changedPageFields'], {'2': ['warnings']})
        self.assertEqual(result['changedReportFields'], ['warnings'])
