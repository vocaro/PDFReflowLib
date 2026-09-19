import Foundation

/// Where each stage's work falls in a conversion's progress fraction. The fractions are a
/// monotonic work estimate, not a time estimate; they reach 1 only when the finished EPUB has
/// been published. Every constant the three stages used to hold separately lives here, and the
/// arithmetic is unchanged so reported values are the same doubles as before.
enum ProgressBudget {
    /// The pipeline's own fraction: extraction, then reconstruction.
    static let extractionShare = 0.6875
    static let reconstructionShare = 0.3125

    /// Progress of the pipeline while extracting or recognizing `page` of `total`. Recognition of a
    /// page is reported before that page's extraction completes, so it uses the page's start.
    static func pipeline(extractedPages: Int, of total: Int) -> Double {
        extractionShare * Double(extractedPages) / Double(total)
    }

    static func pipeline(reconstructedPages: Int, of total: Int) -> Double {
        extractionShare + reconstructionShare * Double(reconstructedPages) / Double(total)
    }

    /// The conversion's fraction: opening, then the pipeline, then writing, then completion.
    static let openingEnd = 0.02
    static let pipelineShare = 0.80
    static let pipelineEnd = 0.82
    static let writingShare = 0.17

    /// Overall progress for a pipeline fraction. Clamped to `pipelineEnd` because
    /// `openingEnd + pipelineShare * 1` rounds above it in binary, and the first writing update
    /// must not step backward.
    static func overall(pipeline fraction: Double) -> Double {
        min(pipelineEnd, openingEnd + pipelineShare * fraction)
    }

    static func overall(writing fraction: Double) -> Double {
        pipelineEnd + writingShare * fraction
    }

    /// The writer's own fraction: serialization of the blocks, then metadata, then archive entries.
    static let serializationShare = 0.45
    static let packagingStart = 0.5

    static func writer(serializedBlocks: Int, of total: Int) -> Double {
        serializationShare * Double(serializedBlocks) / Double(total)
    }

    static func writer(archivedEntries: Int, of total: Int) -> Double {
        packagingStart + (1 - packagingStart) * Double(archivedEntries) / Double(total)
    }
}
