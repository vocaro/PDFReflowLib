import Foundation

/// What the conversion will do about one page's text, decided from its evidence and the OCR
/// policy before any recognition runs.
enum RecognitionPlan: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        /// Recognition replaces whatever text the page had.
        case replace
        /// A layer that misreads `misread` of its `words` words in place is recognized again and
        /// the better reading kept (#7).
        case compare(misread: Int, words: Int)
        /// A sparse layer holding `englishWords` English words that passed every test is
        /// recognized to check it (#216): it stands unless the recognition reads as noise, which
        /// shows the page's writing is handwriting the layer does not transcribe.
        case verify(englishWords: Int)
    }

    /// The extracted page stands; no recognition.
    case keepExtracted
    /// Recognize the page image. `keepCropsIfUnread` is set for a page recognized only because
    /// its art is writing (#176): when recognition reads nothing, the page keeps the crops it was
    /// extracted with instead of becoming one page-sized image.
    case recognize(Mode, keepCropsIfUnread: Bool)

    var recognizes: Bool { self != .keepExtracted }
    /// The layer stands unless recognition proves it worse: a comparison or a verification.
    var compares: Bool { if case .recognize(let mode, _) = self { mode.keepsLayer } else { false } }
}

/// What recognition of a page produced. Cancellation is not an outcome; it propagates.
enum RecognitionOutcome {
    case read(OCRReader.Result)
    case failed
}

/// The page as the conversion will carry it after the plan and its outcome are reconciled.
enum PageDisposition: Equatable {
    /// The extracted page stands, prepared as an unverified or retained layer.
    case keptLayer
    /// A drawn-text page whose recognition read nothing keeps its extracted crops untouched.
    case keptAsExtracted
    /// Recognition replaces the page's text. `resolve` never makes one of a reading with no
    /// lines: a page whose recognition read nothing keeps its crops or becomes an image (#222).
    case replaced(OCRReader.Result)
    /// The page is preserved as an image and reflows nothing.
    case pageImage

    /// What became of native text the page could not map to Unicode, for the `damagedTextEncoding`
    /// message. Only a disposition knows it: the plan alone cannot say whether recognition ran,
    /// read anything, or was believed (#221).
    var encodingOutcome: PageWarning.EncodingOutcome {
        switch self {
        case .keptLayer, .keptAsExtracted: .retained
        case .replaced: .replaced
        case .pageImage: .pageImage
        }
    }

    func apply(to content: inout PageContent) {
        switch self {
        case .keptLayer, .keptAsExtracted:
            break
        case .replaced(let recognized):
            content.lines = recognized.lines
            content.recognized = true
            content.hasSyntheticTextStyle = false
            content.preservePageReference = true
            content.graphics = recognized.tables
            content.recognizedTables = recognized.tableCells
        case .pageImage:
            content.lines = []
            content.requiresPageImage = true
        }
    }
}

/// The judgments of recognized text that `RecognitionPolicy.resolve` needs, injectable so the
/// resolution can be tested without the system lexicon.
struct RecognitionJudge: Sendable {
    /// Whether the recognition reads as noise rather than English (`judgeRecognized`).
    var finding: @Sendable ([TextLine]) -> TextLayerPlausibility.Finding?
    /// Whether the recognition misreads a smaller share of its words than the layer (`readsBetter`).
    var readsBetter: @Sendable (_ lines: [TextLine], _ misread: Int, _ words: Int) -> Bool
    /// Whether a recognition too short for `finding` reads as noise beside the sparse layer it
    /// verifies (`judgeRecognized(lines:besideLayer:language:)`, #216). None by default.
    var findingBesideLayer: @Sendable (_ lines: [TextLine], _ layer: EnglishText.WordCounts)
        -> TextLayerPlausibility.Finding? = { _, _ in nil }

    static func english(language: String) -> RecognitionJudge {
        RecognitionJudge(finding: { TextLayerPlausibility.judgeRecognized(lines: $0, language: language) },
                         readsBetter: { TextLayerPlausibility.readsBetter($0, than: $1, of: $2, language: language) },
                         findingBesideLayer: {
                             TextLayerPlausibility.judgeRecognized(lines: $0, besideLayer: $1, language: language)
                         })
    }
}

enum RecognitionPolicy {
    struct Resolution: Equatable {
        var disposition: PageDisposition
        /// Every warning the page's text judgments and recognition raise, in emission order.
        var warnings: [PageWarning]
    }

    /// Whether the policy asks for recognition of a page with this evidence.
    static func plan(_ evidence: PageEvidence, policy: ConversionOptions.OCRPolicy) -> RecognitionPlan {
        guard !evidence.requiresPageImage else { return .keepExtracted }
        guard needsRecognition(evidence, policy: policy) else {
            // A sparse layer that passed every test can still be the printed title and caption of a
            // handwritten page, which only recognition of the page tells from a photograph's
            // labels (#216). Only the judging policy verifies it.
            if policy.imageBackedLayerRule == .judge, let english = evidence.sparseLayerWords {
                return .recognize(.verify(englishWords: english), keepCropsIfUnread: false)
            }
            return .keepExtracted
        }
        var mode = RecognitionPlan.Mode.replace
        // A layer that reads as English but misreads its words in place (#7) is recognized
        // again and the better reading kept: recognition of a faint carbon typescript misreads
        // as much as the layer does, of a photographed document far less. Only the judging
        // policy compares; the retrying policy and `.always` replace outright.
        if policy.imageBackedLayerRule == .judge, case .misreadWords(let misread, let words, _)? = evidence.implausibleLayer {
            mode = .compare(misread: misread, words: words)
        }
        return .recognize(mode, keepCropsIfUnread: evidence.drawnText)
    }

    private static func needsRecognition(_ evidence: PageEvidence, policy: ConversionOptions.OCRPolicy) -> Bool {
        switch policy {
        case .never: false
        case .always: true
        case .automatic, .automaticIncludingImageBackedText, .automaticKeepingImageBackedText:
            evidence.lacksReadableText
                || (policy.imageBackedLayerRule == .alwaysRetry && evidence.imageBackedText)
                || (policy.imageBackedLayerRule == .judge && evidence.implausibleLayer != nil)
        }
    }

    /// Reconciles the plan with what recognition produced (nil when none ran) into the page's
    /// disposition and its warnings, in the order the conversion reports them: the encoding
    /// diagnosis, then the unverified-layer notice for a layer that stands, then what became
    /// of the layer and of the recognition.
    static func resolve(_ plan: RecognitionPlan, evidence: PageEvidence, outcome: RecognitionOutcome?,
                        judge: RecognitionJudge) -> Resolution {
        let (disposition, outcomeWarnings) = reconcile(plan, finding: evidence.implausibleLayer,
                                                       sparseLayer: evidence.sparseLayer,
                                                       outcome: outcome, judge: judge)
        var warnings: [PageWarning] = []
        if evidence.damagedEncoding {
            warnings.append(.damagedTextEncoding(disposition.encodingOutcome))
        }
        // The layer stands as unverified text only while the plan keeps it (or compares it and
        // it wins); a replaced layer takes its review notice with it.
        if !plan.recognizes || plan.compares, !evidence.requiresPageImage, evidence.imageBackedText,
           disposition == .keptLayer {
            warnings.append(.unverifiedTextLayer)
        }
        warnings += outcomeWarnings
        return Resolution(disposition: disposition, warnings: warnings)
    }

    private static func reconcile(_ plan: RecognitionPlan, finding: TextLayerPlausibility.Finding?,
                                  sparseLayer: EnglishText.WordCounts?,
                                  outcome: RecognitionOutcome?, judge: RecognitionJudge) -> (PageDisposition, [PageWarning]) {
        guard case .recognize(let mode, let keepCropsIfUnread) = plan, let outcome else {
            return (.keptLayer, finding.map { [.implausibleTextLayer($0, .retained)] } ?? [])
        }
        // The implausible-layer warning states what became of the layer, known only after
        // recognition is attempted (or, for a retained layer, never attempted at all). A verified
        // layer has a finding only once its recognition has read as noise.
        func layer(_ outcome: TextLayerPlausibility.Outcome) -> [PageWarning] {
            if case .verify(let english) = mode {
                return outcome == .implausibleRecognition
                    ? [.implausibleTextLayer(.unreadWriting(englishWords: english), outcome)] : []
            }
            return finding.map { [.implausibleTextLayer($0, outcome)] } ?? []
        }
        switch outcome {
        case .read(let recognized):
            if recognized.lines.isEmpty, keepCropsIfUnread {
                // Recognition read nothing from a page whose art is its only writing: say so, and
                // leave the extracted page (its crops and its folio) exactly as it was. The layer's
                // own finding is still reported, so the page can be reviewed (#220).
                return (.keptAsExtracted, layer(.keptAsExtracted) + [.ocrFailed(.unreadDrawnText)])
            }
            // Recognition that does not read as English is noise, not a transcription (#7): a
            // reader is better served by the page image than by text made of it.
            var recognitionFinding = judge.finding(recognized.lines)
            if recognitionFinding == nil, case .verify = mode, let sparseLayer {
                // A reading too short to judge alone is judged beside the layer it verifies: where
                // both read under half English, together they are long enough to judge (#216).
                recognitionFinding = judge.findingBesideLayer(recognized.lines, sparseLayer)
            }
            // Recognition that reads as noise beside a sparse layer is handwriting neither reading
            // transcribes (#216): the page image serves the reader, whatever the layer's own finding.
            // A reading of nothing is not noise; the layer stands over it.
            if let recognitionFinding, mode == .replace || (sparseLayer != nil && !recognized.lines.isEmpty) {
                return (.pageImage, [.implausibleRecognition(recognitionFinding)] + layer(.implausibleRecognition))
            }
            if case .verify = mode {
                // The sparse layer stands: recognition read the page's writing as English, or read
                // nothing at all.
                return (.keptLayer, [])
            }
            if case .compare(let misread, let words) = mode,
               !(recognitionFinding == nil && judge.readsBetter(recognized.lines, misread, words)) {
                // The damaged layer stands: recognition read no better.
                return (.keptLayer, layer(.keptOverRecognition))
            }
            if recognized.lines.isEmpty {
                // Recognition succeeded and read nothing. There is no transcription to announce and
                // nothing for the page to reflow, so it is preserved as an image and is not counted
                // as a recognized page (#222).
                return (.pageImage, layer(.pageImage) + [.ocrFailed(.noText)])
            }
            var warnings = layer(.replaced)
            warnings.append(.ocrUsed)
            // The transcription the reader is being given does not account for all of the page's
            // writing (#116). Only this disposition reports it: a reading that was discarded for
            // the page image or for the layer is not what the reader gets, and those outcomes say
            // so themselves. The warning states what the reading finally left out, after any band
            // retry, not what the retry set out to recover.
            if let fraction = recognized.uncoveredTextFraction {
                warnings.append(.incompleteRecognition(uncoveredFraction: fraction,
                                                       retriedInBands: recognized.retriedInBands))
            }
            return (.replaced(recognized), warnings)
        case .failed:
            if mode.keepsLayer {
                return (.keptLayer, layer(.keptOverRecognition) + [.ocrFailed(.layerRetained)])
            }
            if keepCropsIfUnread {
                return (.keptAsExtracted, layer(.keptAsExtracted) + [.ocrFailed(.unreadDrawnText)])
            }
            return (.pageImage, layer(.pageImage) + [.ocrFailed(.pageImage)])
        }
    }
}

private extension RecognitionPlan.Mode {
    var keepsLayer: Bool {
        switch self {
        case .compare, .verify: true
        case .replace: false
        }
    }
}
