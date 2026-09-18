import unittest

from check_pdfkit_gate import violations, violations_in


class PDFKitGateTests(unittest.TestCase):
    def test_repository_reads_pdfkit_text_and_makes_fonts_only_inside_the_gate(self):
        # #21: one ungated read, font or CoreText line anywhere in the process can abort a gated
        # extraction with PDFKit's NSFont exception. Route new ones through withExtractionLock
        # (library) or pdfKitGated (tests).
        self.assertEqual(violations(), [])

    def test_calls_in_a_gate_closure_pass(self):
        source = '''
        @Test func reads() throws {
            let names = pdfKitGated { page.selection(for: rect)?.selectionsByLine() }
            let font = pdfKitGated { TestFont(name: "Helvetica", size: 10) }!
            try NativeTextReader.withExtractionLock { _ = page.numberOfCharacters }
        }
        '''
        self.assertEqual(violations_in(source), [])

    def test_ungated_reads_fonts_and_coretext_are_reported(self):
        source = '''
        @Test func reads() {
            let text = page.string
            let lines = selection.selectionsByLine()
            let attributed = line.attributedString
            let font = NSFont(name: "Helvetica", size: 12)
            let other = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            CTLineDraw(CTLineCreateWithAttributedString(value), context)
        }
        '''
        found = violations_in(source)
        self.assertEqual(len(found), 7, found)
        self.assertTrue(all('in `reads`' in v for v in found))

    def test_a_private_helper_is_reported_where_an_ungated_caller_reaches_it(self):
        source = '''
        private func native(_ page: PDFPage) -> [String] {
            func lines() -> [PDFSelection] { page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine() ?? [] }
            return lines().compactMap(\\.string)
        }
        @Test func gatedCaller() { _ = pdfKitGated { native(page) } }
        @Test func ungatedCaller() { _ = native(page) }
        '''
        found = violations_in(source)
        self.assertEqual(len(found), 1, found)
        self.assertIn('via `lines` via `native` in `ungatedCaller`', found[0])

    def test_an_internal_function_holding_a_call_is_reported_even_when_its_callers_gate_it(self):
        source = '''
        static func lines(on page: PDFPage) -> Int { page.numberOfCharacters }
        func caller() throws { _ = try NativeTextReader.withExtractionLock { lines(on: page) } }
        '''
        self.assertEqual(len(violations_in(source)), 1)

    def test_comments_strings_fixture_methods_and_copies_are_not_calls(self):
        source = '''
        // page.string and CTLineDraw( in a comment
        func copy(_ attributed: NSAttributedString) -> NSAttributedString {
            let label = "selectionsByLine() and NSFont(name: x, size: 1)"
            let fixture = source.attributedString()
            return NSMutableAttributedString(attributedString: attributed)
        }
        '''
        self.assertEqual(violations_in(source), [])


if __name__ == '__main__':
    unittest.main()
