import Foundation
import Testing
@testable import PDFReflowLib

// Vision returns Cyrillic from a page declared English; only the look-alikes are repaired (#168).
// It returns Latin from an all-capital page declared Russian; the mirror repairs those (#108).

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
    // A document that is not declared English is never touched by the English rule, so real
    // Cyrillic survives even where every letter happens to have a Latin look-alike; the Russian
    // rule of #108 touches only Latin letters, so the same reading is still returned as read.
    #expect(OCRReader.repairedScript("СОТ РОТ", language: "ru") == "СОТ РОТ")
    #expect(OCRReader.repairedScript("СОТ РОТ", language: "en") == "COT POT")
    // Russian prose reaches the English rule as words holding letters with no look-alike, and
    // keeps them.
    #expect(OCRReader.repairedScript("привет мир", language: "en") == "привет мир")
    // Ordinary English is returned unchanged and allocates no new string work to notice it.
    #expect(OCRReader.repairedScript("The quick brown fox", language: "en") == "The quick brown fox")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/108")) func cyrillicCapitalsReadAsLatinAreReturnedToTheirScript() {
    // Synthetic Russian capitals as Vision returns them under `ru-RU`: every letter has a Latin
    // look-alike, and the whole line comes back Latin (`measurements/ocr-language-options`).
    #expect(OCRReader.repairedScript("KOMAP TAPA", language: "ru") == "КОМАР ТАРА")
    #expect(OCRReader.repairedScript("MOPE COPT XOP", language: "ru") == "МОРЕ СОРТ ХОР")
    #expect(OCRReader.repairedScript("BOPOH TOPT MAMA", language: "ru-RU") == "ВОРОН ТОРТ МАМА")
    // The same words with a letter Vision left in its script: a token of both scripts is a
    // word of neither, and is rewritten whatever its case.
    #expect(OCRReader.repairedScript("MOСKВА", language: "ru") == "МОСКВА")
    #expect(OCRReader.repairedScript("МОPЕ COPT ХОР", language: "ru") == "МОРЕ СОРТ ХОР")
    #expect(OCRReader.repairedScript("ТАСС СССР HАТО", language: "ru") == "ТАСС СССР НАТО")
    #expect(OCRReader.repairedScript("моpe compact хop", language: "ru") == "море compact хор")
    // Punctuation and digits ride along; a word with a letter of no look-alike was read right.
    #expect(OCRReader.repairedScript("TOPT, KOMAP!", language: "ru") == "ТОРТ, КОМАР!")
    #expect(OCRReader.repairedScript("ЖУРНАЛ ДОМ", language: "ru") == "ЖУРНАЛ ДОМ")
    // Every language written in Cyrillic has the rule, by its script rather than by a list.
    for language in ["uk", "uk-UA", "bg", "sr", "sr-Cyrl", "mk", "be", "kk", "mn", "ru_RU"] {
        #expect(OCRReader.repairedScript("KOMAP TAPA", language: language) == "КОМАР ТАРА", "\(language)")
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/108")) func latinThePageDrawsInACyrillicDocumentIsKept() {
    // A Latin letter with no Cyrillic look-alike keeps its whole token: Vision reads `NASA`
    // beside a Russian word as Latin because that is what the page draws.
    #expect(OCRReader.repairedScript("KOMAP NASA", language: "ru") == "КОМАР NASA")
    #expect(OCRReader.repairedScript("MOCKBA USA", language: "ru") == "МОСКВА USA")
    #expect(OCRReader.repairedScript("Отчёт NASA за год.", language: "ru") == "Отчёт NASA за год.")
    // `I`, `J` and `S` have look-alikes only in alphabets other than Russian's, so they count
    // as letters with none: `XIX` and `ISO` stay as drawn.
    #expect(OCRReader.repairedScript("XIX BEK", language: "ru") == "XIX ВЕК")
    #expect(OCRReader.repairedScript("ISO 9001", language: "ru") == "ISO 9001")
    // A Roman numeral of X, C and M alone is returned by Vision as the Latin it is, beside the
    // Cyrillic word it misread, and stays a numeral.
    #expect(OCRReader.repairedScript("XX BEK", language: "ru") == "XX ВЕК")
    #expect(OCRReader.repairedScript("ГЛАВА XX", language: "ru") == "ГЛАВА XX")
    #expect(OCRReader.repairedScript("M. ГОРЬКИЙ", language: "ru") == "M. ГОРЬКИЙ")
    // Lower-case Latin words are read as what they are under `ru`, and lower-case Cyrillic is
    // read correctly, so a lower-case Latin token is never guessed at.
    #expect(OCRReader.repairedScript("комар tax", language: "ru") == "комар tax")
    #expect(OCRReader.repairedScript("tax compact", language: "ru") == "tax compact")
    #expect(OCRReader.repairedScript("Tax", language: "ru") == "Tax")
    // The cost of that: `хор` read wholly as Latin `xop` at scan size is a lower-case Latin
    // token too, and stays one, while `моpe` beside it is mixed and is repaired.
    #expect(OCRReader.repairedScript("моpe compact xop", language: "ru") == "море compact xop")
    // A reading with no Latin letter at all is returned as it was, allocating nothing.
    #expect(OCRReader.repairedScript("Мама мыла раму.", language: "ru") == "Мама мыла раму.")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/108")) func anAllCapitalLatinWordOfLookAlikesIsRewrittenWithTheMisreading() {
    // The risk the rule accepts, pinned so that narrowing it is a decision and not an accident:
    // Vision under `ru` returns `TAX COMPACT` exactly as it returns the misread `ТАХ`, and no
    // reading of the token can tell them apart. Each renders the same either way.
    #expect(OCRReader.repairedScript("TAX COMPACT", language: "ru") == "ТАХ СОМРАСТ")
    #expect(OCRReader.repairedScript("NASA MOCK", language: "ru") == "NASA МОСК")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/108")) func theCyrillicRuleReachesOnlyCyrillicScriptLanguages() {
    // The declared language decides by its script: Serbian in Latin, Uzbek, Greek and every
    // Latin-script language are outside it, and an English document keeps the English rule.
    for language in ["en", "en-US", "fr", "sr-Latn", "uz", "el", "zh-Hans", "ar", "tlh", ""] {
        #expect(OCRReader.repairedScript("KOMAP TAPA", language: language) == "KOMAP TAPA", "\(language)")
        #expect(OCRReader.repairedScript("TAX COMPACT", language: language) == "TAX COMPACT", "\(language)")
        #expect(!OCRReader.declaresCyrillicScript(language), "\(language)")
    }
    for language in ["ru", "ru-RU", "uk", "bg", "sr", "sr-Cyrl", "mk", "be", "kk", "ky", "tg", "mn", "uz-Cyrl"] {
        #expect(OCRReader.declaresCyrillicScript(language), "\(language)")
    }
    #expect(OCRReader.repairedScript("МАУВЕ NOT", language: "en") == "MAYBE NOT")
    #expect(OCRReader.repairedScript("МАУВЕ NOT", language: "ru") == "МАУВЕ NOT")
}
