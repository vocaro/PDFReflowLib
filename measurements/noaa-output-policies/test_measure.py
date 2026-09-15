"""Negative controls for the full-NOAA measurement's independent content comparison."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from PIL import Image

spec = importlib.util.spec_from_file_location('measure', Path(__file__).with_name('measure.py'))
measure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(measure)


class MeasurementTests(unittest.TestCase):
    def test_cancellation_requires_trigger_and_no_false_completion(self):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            for stage in ['reconstructing', 'writing']:
                (directory / f'cancel-{stage}').mkdir()
                (directory / f'cancel-{stage}.json').write_text(json.dumps({
                    'sourceSHA256': measure.SOURCE_SHA256, 'sourcePages': 1834,
                    'cancelled': True, 'outputAbsent': True, 'stagingRemoved': True}))
                log = ''.join(f'0.2 extracting page {p}/1834 cancel=false\n' for p in range(1, 1835))
                count = 900 if stage == 'reconstructing' else 1834
                log += ''.join(f'0.5 reconstructing page {p}/1834 cancel=' +
                    ('true' if stage == 'reconstructing' and p == count else 'false') + '\n'
                    for p in range(1, count + 1))
                if stage == 'writing':
                    log += '0.82 writing page 0/1834 cancel=true\n'
                (directory / f'cancel-{stage}.log').write_text(log)
            self.assertTrue(measure.check_cancellation(directory)['writing']['triggerVerified'])
            path = directory / 'cancel-writing.log'
            original = path.read_text()
            for altered in [original + '1.0 completed page 0/1834 cancel=false\n',
                            original.replace('cancel=true', 'cancel=false')]:
                path.write_text(altered)
                with self.assertRaises(AssertionError):
                    measure.check_cancellation(directory)

    def test_expected_failure_rejects_false_completion_and_staging(self):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            (directory / 'result.json').write_text(json.dumps({'conversionExitCode': 1,
                'runPassed': False, 'options': 'library defaults',
                'case': {'sha256': measure.SOURCE_SHA256, 'pages': 1834}}))
            log = ''.join(f'20% extracting page {page}/1834\n' for page in range(1, 1835))
            log += '65% reconstructing page 599/1834\nConversion resource limit: image output bytes\n'
            path = directory / 'progress.log'
            path.write_text(log)
            self.assertTrue(measure.check_default(directory)['expectedImageBudgetFailure'])
            path.write_text(log + '100% completed\n')
            with self.assertRaises(AssertionError):
                measure.check_default(directory)
            path.write_text(log)
            (directory / '.pdfreflow-leftover').mkdir()
            with self.assertRaises(AssertionError):
                measure.check_default(directory)

    def make_epub(self, directory, *, omitted_page=None, caption_only=False, wrong_page=False):
        path = Path(directory) / 'test.epub'
        png = Path(directory) / 'pixel.png'
        Image.new('RGB', (2, 3), (20, 80, 180)).save(png)
        body = []
        for number in range(1, 1835):
            if number == omitted_page:
                continue
            body.append(f'<span epub:type="pagebreak" id="page-{number}"/>')
            source_page = 80 if wrong_page and number == 81 else number
            if wrong_page and number == 80:
                source_page = 81
            if source_page in measure.PHRASES:
                tag = 'figcaption' if caption_only else 'p'
                body.append(f'<{tag}>{" ".join(measure.PHRASES[source_page])}</{tag}>')
                body.append('<figure><img src="images/pixel.png"/></figure>')
            elif source_page in measure.UNREFLOWED_SOURCE:
                body.append('<figure><img src="images/pixel.png"/></figure>')
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('EPUB/package.opf', '<package xmlns="http://www.idpf.org/2007/opf">'
                '<manifest><item id="one" href="one.xhtml"/></manifest>'
                '<spine><itemref idref="one"/></spine></package>')
            archive.writestr('EPUB/one.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml" '
                'xmlns:epub="http://www.idpf.org/2007/ops"><body>' + ''.join(body) + '</body></html>')
            archive.write(png, 'EPUB/images/pixel.png')
        return path

    def test_source_text_image_and_all_page_controls(self):
        with tempfile.TemporaryDirectory() as directory:
            result = measure.inspect(self.make_epub(directory))
            self.assertEqual(len(result['pages']), 1834)
            self.assertEqual(result['images']['EPUB/images/pixel.png']['size'], (2, 3))
            for alteration in [{'omitted_page': 900}, {'caption_only': True}, {'wrong_page': True}]:
                with self.subTest(alteration=alteration), self.assertRaises(AssertionError):
                    measure.inspect(self.make_epub(directory, **alteration))

    def test_comparison_rejects_semantic_image_and_resolution_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            original = measure.inspect(self.make_epub(directory))
        self.assertTrue(measure.compare(original, original)['allImageOrderAndDimensionsIdentical'])
        for kind in ['markup', 'text', 'ownership', 'pixels', 'size']:
            changed = copy.deepcopy(original)
            if kind == 'markup':
                changed['chapterHashesIgnoringImageExtension'][0] = 'different semantics'
            elif kind == 'text':
                changed['pages'][80]['text'] = 'wrong'
            elif kind == 'ownership':
                changed['pages'][80]['images'] = []
            elif kind == 'pixels':
                changed['images']['EPUB/images/pixel.png']['sha256'] = 'different image'
            else:
                changed['images']['EPUB/images/pixel.png']['size'] = (1, 1)
            with self.subTest(kind=kind), self.assertRaises(AssertionError):
                measure.compare(original, changed)


if __name__ == '__main__':
    unittest.main()
