import Foundation

/// Holds extraction-pass pages in the workspace until the reconstruction pass needs them.
///
/// Pages are stored once, in order, and loaded once, in the same order, so retained page
/// memory is bounded to the page being reconstructed and its predecessor. The page-retention
/// measurement selected spilling over keeping pages resident and over repeating extraction;
/// see `measurements/page-retention/record.md`. The owner deletes the workspace afterwards.
final class PageStore {
    private let directory: URL
    private var directoryExists = false
    /// Pages written to the workspace, whether or not they have been reloaded since.
    private(set) var spilledIndices: Set<Int> = []

    init(directory: URL) {
        self.directory = directory
    }

    func store(_ page: PageContent, at index: Int) throws {
        if !directoryExists {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            directoryExists = true
        }
        // Binary property lists round-trip finite, infinite and NaN doubles, which JSON
        // rejects. Equal values share one slot, so a negative zero can reload as positive
        // zero; no reconstruction step observes the sign of zero.
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(page).write(to: url(index))
        spilledIndices.insert(index)
    }

    func load(at index: Int) throws -> PageContent {
        guard spilledIndices.contains(index) else { preconditionFailure("Page \(index) was never stored") }
        let file = url(index)
        let page = try PropertyListDecoder().decode(PageContent.self, from: Data(contentsOf: file))
        // Each page is reloaded once; removing it bounds workspace disk use.
        try? FileManager.default.removeItem(at: file)
        return page
    }

    /// Reconstruction has loaded every page; the workspace keeps only assets afterwards.
    func finish() {
        if directoryExists {
            try? FileManager.default.removeItem(at: directory)
            directoryExists = false
        }
    }

    private func url(_ index: Int) -> URL { directory.appendingPathComponent("page-\(index).plist") }
}
