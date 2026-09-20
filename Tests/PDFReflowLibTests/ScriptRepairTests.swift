import Foundation
import Testing
@testable import PDFReflowLib

// Vision returns Cyrillic from a page declared English; only the look-alikes are repaired (#168).

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/168")) func cyrillicLookAlikesAreReadAsTheLatinTheyDraw() {
    // The CDC graphic novel's hand-lettered balloons, as Vision returns them.
    #expect(OCRReader.repairedScript("МАУВЕ NOT", language: "en") == "MAYBE NOT")
    #expect(OCRReader.repairedScript("HА HА", language: "en") == "HA HA")
    #expect(OCRReader.repairedScript("UН?", language: "en") == "UH?")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/168")) func aReadingNoSubstitutionCanRepairIsLeftAsRead() {
    // И and Д stand where the page draws U and A, which is a misreading rather than a
    // substitution: every character of these tokens survives untouched.
    for reading in ["НИН?!", "ОКДУ, МАУВЕ NOT", "УДУУ!!", "WHД?", "САОдОКА"] {
        let repaired = OCRReader.repairedScript(reading, language: "en")
        let tokens = zip(reading.split(separator: " "), repaired.split(separator: " "))
        for (before, after) in tokens where before.contains(where: { "ИДид".contains($0) }) {
            #expect(before == after, "a token holding И or Д must be left as read: \(before) -> \(after)")
        }
    }
    // The one token of that line a mapping can prove is still repaired.
    #expect(OCRReader.repairedScript("ОКДУ, МАУВЕ NOT", language: "en") == "ОКДУ, MAYBE NOT")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/168")) func anotherLanguageKeepsItsOwnScript() {
    // A document that is not declared English is never touched, so real Cyrillic survives even
    // where every letter happens to have a Latin look-alike.
    #expect(OCRReader.repairedScript("СОТ РОТ", language: "ru") == "СОТ РОТ")
    #expect(OCRReader.repairedScript("СОТ РОТ", language: "en") == "COT POT")
    // Russian prose reaches the English rule as words holding letters with no look-alike, and
    // keeps them.
    #expect(OCRReader.repairedScript("привет мир", language: "en") == "привет мир")
    // Ordinary English is returned unchanged and allocates no new string work to notice it.
    #expect(OCRReader.repairedScript("The quick brown fox", language: "en") == "The quick brown fox")
}
