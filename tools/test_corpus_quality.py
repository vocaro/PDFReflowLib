import unittest

from check_corpus_quality import assess


class CorpusQualityTests(unittest.TestCase):
    def check(self, *, warnings=(), exit_code=0, error='', output=True, staging=False,
              timed_out=False, identity='source', completed=False, allowed_errors=()):
        case = {'id': 'scan', 'sha256': 'source', 'bytes': 10, 'pages': 200,
                'qualityExpectation': {'warningPages': [74, 150],
                                       'warningCodes': ['unverifiedTextLayer'],
                                       'qualityRejectionDiagnostics': list(allowed_errors)}}
        result = {'case': dict(case, sha256=identity), 'conversionExitCode': exit_code,
                  'runPassed': exit_code == 0, 'timedOut': timed_out}
        report = {'pageCount': 200, 'warnings': list(warnings)}
        return assess(case, result, report, error + ('\n100% completed' if completed else ''),
                      output_exists=output, staging_exists=staging)['passed']

    def test_generic_image_warnings_do_not_claim_quality_detection(self):
        self.assertFalse(self.check(warnings=[{'page': p, 'code': 'imageRegion'} for p in [74, 150]]))

    def test_specific_warnings_required_on_every_reference_page(self):
        warnings = [{'page': p, 'code': 'unverifiedTextLayer'} for p in [74, 150]]
        self.assertTrue(self.check(warnings=warnings))
        self.assertFalse(self.check(warnings=warnings[:1]))
        self.assertFalse(self.check(warnings=warnings, identity='different-source'))
        self.assertFalse(self.check(warnings=warnings, output=False))
        self.assertFalse(self.check(warnings=warnings, staging=True))

    def test_crash_timeout_and_resource_errors_are_not_quality_refusals(self):
        for code, message in [(-9, ''), (1, 'Conversion resource limit: image output'),
                              (1, 'Unlock the PDF before converting it.')]:
            self.assertFalse(self.check(exit_code=code, error=message, output=False))
        self.assertFalse(self.check(exit_code=1, output=False, timed_out=True))

    def test_only_explicit_refusal_without_output_or_completion_passes(self):
        diagnostic = 'Test quality refusal'
        args = dict(exit_code=1, error=diagnostic, output=False, allowed_errors=[diagnostic])
        self.assertTrue(self.check(**args))
        for field, value in [('output', True), ('staging', True), ('completed', True),
                             ('timed_out', True), ('identity', 'different-source'), ('exit_code', 137),
                             ('error', diagnostic + '\nUnrelated fatal error')]:
            self.assertFalse(self.check(**dict(args, **{field: value})))

        self.assertFalse(self.check(**dict(args, error='99% completed\n' + diagnostic)))
