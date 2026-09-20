import Foundation
@testable import PDFReflowLib

/// Reading a reconstructed page's blocks in tests.
func headingTexts(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .heading = $0.content { $0.text } else { nil } }
}

func paragraphTexts(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { $0.text } else { nil } }
}

extension PDFReflowLibPipeline.Result {
    /// The collected document. Only a caller that takes the part stream gets none, and a test
    /// that reads a whole document never does.
    var book: ReflowDocument {
        guard let document else { preconditionFailure("a collected reconstruction has its document") }
        return document
    }
}

/// Collects a conversion's progress events in order.
actor ProgressLog {
    var events: [ConversionProgress] = []
    func append(_ event: ConversionProgress) { events.append(event) }
}
