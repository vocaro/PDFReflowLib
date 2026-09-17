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
    // The bare book language `en` maps to Vision's `en-US`, which is also the recognizer default.
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

@Test func ocrRequestMapsBookLanguagesToSupportedRecognitionLanguages() {
    // #106: book languages are usually bare codes; Vision lists region- or script-qualified ones.
    for (book, vision) in [("en", "en-US"), ("en-US", "en-US"), ("en-GB", "en-US"), ("fr", "fr-FR"),
                           ("fr-FR", "fr-FR"), ("fr-CA", "fr-FR"), ("de", "de-DE"), ("pt", "pt-BR"),
                           ("pt-PT", "pt-BR"), ("ja", "ja-JP"), ("zh", "zh-Hans"), ("zh-Hans", "zh-Hans"),
                           ("zh-TW", "zh-Hant"), ("zh-Hant", "zh-Hant"), ("ru", "ru-RU"), ("ar", "ar-SA")] {
        #expect(OCRReader.recognitionRequest(language: book).textRecognitionOptions.recognitionLanguages
                == [Locale.Language(identifier: vision)], "\(book)")
        #expect(OCRReader.languageFallbackNote(for: book).isEmpty, "\(book)")
    }
    let defaults = RecognizeDocumentsRequest().textRecognitionOptions.recognitionLanguages
    for book in ["tlh", "el", "he", "x-private"] {
        #expect(OCRReader.recognitionLanguage(for: book) == nil, "\(book)")
        #expect(OCRReader.recognitionRequest(language: book).textRecognitionOptions.recognitionLanguages == defaults)
        #expect(OCRReader.languageFallbackNote(for: book)
                == " Vision does not recognize the book language \(book); OCR used its default language (en-US) with automatic language detection.")
    }
}
