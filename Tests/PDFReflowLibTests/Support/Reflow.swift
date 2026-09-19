import Foundation
@testable import PDFReflowLib

/// Reading a reconstructed page's blocks in tests.
func headingTexts(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .heading = $0.content { $0.text } else { nil } }
}

func paragraphTexts(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { $0.text } else { nil } }
}

/// Collects a conversion's progress events in order.
actor ProgressLog {
    var events: [ConversionProgress] = []
    func append(_ event: ConversionProgress) { events.append(event) }
}
