import Foundation
import Testing
import Vision
@testable import PDFReflowLib

// The request every recognized page is read with, inspected without recognizing anything (#108).

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/108")) func languageCorrectionIsRequestedOnlyWhenTheOptionSaysSo() {
    // Off by default: the measured cost to codes, dates and names keeps it there.
    let plain = OCRReader.recognitionRequest(options: ConversionOptions())
    #expect(plain.textRecognitionOptions.useLanguageCorrection == false)
    var options = ConversionOptions()
    options.ocrLanguageCorrection = true
    let corrected = OCRReader.recognitionRequest(options: options)
    #expect(corrected.textRecognitionOptions.useLanguageCorrection)
    // Nothing else about the request moves with the option: the same pages are read at the
    // same language, with the same detection, so the option changes only what it says it does.
    var withoutCorrection = corrected.textRecognitionOptions
    withoutCorrection.useLanguageCorrection = false
    #expect(withoutCorrection == plain.textRecognitionOptions)
    #expect(corrected.textRecognitionOptions.recognitionLanguages == plain.textRecognitionOptions.recognitionLanguages)
    #expect(corrected.revision == plain.revision)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/108")) func aConversionThatCorrectedWordsSaysSoOnEveryRecognizedPage() {
    // The report has no field for the option, so its `ocrUsed` warnings carry it; with the
    // option off they say what they always have, under either reference policy.
    for references in [ConversionOptions.ReferenceImagePolicy.automatic, .never] {
        var options = ConversionOptions()
        options.referenceImages = references
        let plain = ConversionWarnings.warning(.ocrUsed, page: 3, options: options).message
        #expect(plain.hasPrefix("Text is OCR transcription. "))
        #expect(!plain.contains("language correction"))
        options.ocrLanguageCorrection = true
        let corrected = ConversionWarnings.warning(.ocrUsed, page: 3, options: options).message
        #expect(corrected.contains("language correction on"))
        #expect(corrected.hasSuffix(String(plain.dropFirst("Text is OCR transcription. ".count))),
                "the reference-policy tail is the same either way")
    }
}
