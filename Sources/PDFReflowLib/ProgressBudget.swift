import Foundation

/// Where each stage's work falls in a conversion's progress fraction. The fractions are a
/// monotonic work estimate, not a time estimate; they reach 1 only when the finished EPUB has
/// been published. Every constant the three stages used to hold separately lives here. The
/// opening, pipeline and publication arithmetic is the same as when each stage held its own;
/// writing lost its serialization share when the writer began consuming blocks as they are made.
enum ProgressBudget {
    /// The pipeline's own fraction: extraction, then reconstruction. Reconstruction hands each
    /// page's blocks straight to the writer, so its share now covers their serialization too;
    /// the shares themselves are unchanged, because they estimate work, not time.
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

    /// The writer's own fraction: the archive entries. Serializing a block is now the work of
    /// the pass that produces it, so it is reported as reconstruction, not as writing.
    static func writer(archivedEntries: Int, of total: Int) -> Double {
        Double(archivedEntries) / Double(total)
    }
}
