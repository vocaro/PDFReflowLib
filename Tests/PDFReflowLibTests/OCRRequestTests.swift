import Foundation
import Testing
import Vision
@testable import PDFReflowLib

// #94: every recognition setting that affects transcription is written out, so an SDK default
// change cannot silently alter OCR. Compute devices stay automatic (see OCRReader).

@Test func ocrRequestPinsRevisionAndTextRecognitionOptions() {
    let request = OCRReader.recognitionRequest(language: "en")
    #expect(request.revision == .revision1)
    let options = request.textRecognitionOptions
    #expect(options.useLanguageCorrection == false)
    #expect(options.automaticallyDetectLanguage == true)
    #expect(options.minimumTextHeightFraction == 0.03125)
    #expect(options.maximumCandidateCount == 3)
    #expect(options.customWords.isEmpty)
    // Vision lists region-qualified languages (`en-US`), so the bare book language `en` does not
    // match and the recognizer keeps its default, which is US English.
    #expect(options.recognitionLanguages == [Locale.Language(identifier: "en-US")])
    for stage in request.supportedComputeStageDevices.keys {
        #expect(request.computeDevice(for: stage) == nil)
    }
}

@Test func ocrRequestPinnedValuesAreTheSDKDefaults() {
    // Pinning must not change output: the written values equal an unconfigured request's, apart
    // from language correction, which the converter has always turned off.
    var defaults = RecognizeDocumentsRequest()
    defaults.textRecognitionOptions.useLanguageCorrection = false
    #expect(OCRReader.recognitionRequest(language: "en") == defaults)
    #expect(RecognizeDocumentsRequest.supportedRevisions.contains(.revision1))
}

@Test func ocrRequestAppliesOnlyAnExactlySupportedLanguage() {
    let defaults = RecognizeDocumentsRequest().textRecognitionOptions.recognitionLanguages
    #expect(OCRReader.recognitionRequest(language: "tlh").textRecognitionOptions.recognitionLanguages == defaults)
    #expect(OCRReader.recognitionRequest(language: "fr-FR").textRecognitionOptions.recognitionLanguages
            == [Locale.Language(identifier: "fr-FR")])
}
