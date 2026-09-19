import Foundation

/// Independent Apple-only PDF-to-EPUB 3 converter. Work runs on this actor, not the main actor.
/// Each call owns its PDFDocument and staging directory. Cancellation uses Swift Task cancellation.
/// This library serializes its own PDFKit text extraction to mitigate a PDFKit crash under
/// concurrent attributed-text extraction (`NSInvalidArgumentException`, nil `NSFont`; Apple
/// FB24796210, see `doc/architecture.md`'s "Reconstruction boundary"). That mitigation only
/// covers this library's own PDFKit calls: a host application making a font, laying out text
/// with CoreText, or reading PDFKit text on its own thread while a conversion runs can still
/// trigger the same underlying SDK bug. This is a real, currently open limitation.
public actor PDFConverter {
    public init() {}

    /// Converts a local PDF to a new local EPUB. Existing destinations are never overwritten.
    /// Progress callbacks are serialized for this call and may hop to MainActor to update a UI.
    /// Callers own security-scoped access and must keep it alive until this method returns.
    public func convert(
        from source: URL, to destination: URL, options: ConversionOptions = .init(),
        progress: @escaping @Sendable (ConversionProgress) async -> Void = { _ in }
    ) async throws -> ConversionReport {
        try validate(options, source: source, destination: destination)
        try Task.checkCancellation()
        await progress(.init(stage: .opening, fractionCompleted: 0, page: nil, totalPages: 0))
        let inputSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard Int64(inputSize) <= options.maximumInputBytes else {
            throw ConversionError.resourceLimit("input bytes")
        }
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".pdfreflow-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options, workspace: staging) { event in
            await progress(.init(stage: event.stage, fractionCompleted: ProgressBudget.overall(pipeline: event.fractionCompleted),
                page: event.page, totalPages: event.totalPages))
        }
        let total = result.pageCount
        let archive = try await EPUBWriter.write(result.document, maximumOutputBytes: options.maximumOutputBytes,
            directory: staging, packageIdentifier: options.packageIdentifier,
            modificationDate: options.modificationDate) { fraction in
                await progress(.init(stage: .writing, fractionCompleted: ProgressBudget.overall(writing: fraction), page: nil, totalPages: total))
            }
        try Task.checkCancellation()
        if let limit = options.maximumEPUBBytes {
            let bytes = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard Int64(bytes) <= limit else { throw ConversionError.resourceLimit("final EPUB file bytes") }
        }
        // Same-parent rename publishes an entire EPUB, never a half-written destination.
        try fm.moveItem(at: archive, to: destination)
        let report = ConversionReport(outputURL: destination, pageCount: total, reflowedPageCount: result.reflowedPageCount,
            recognizedPageCount: result.recognizedPageCount, imageCount: result.document.assets.count, warnings: result.warnings)
        await progress(.init(stage: .completed, fractionCompleted: 1, page: nil, totalPages: total))
        return report
    }

    private func validate(_ options: ConversionOptions, source: URL, destination: URL) throws {
        guard source.isFileURL, destination.isFileURL else {
            throw ConversionError.invalidOptions("input and output must be local file URLs")
        }
        // Each bound is reported by name, so a client learns which option to fix.
        guard options.language.range(of: "^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$", options: .regularExpression) != nil else {
            throw ConversionError.invalidOptions("language must be a BCP 47 tag such as en or en-US")
        }
        guard options.rasterDPI.isFinite, (72...600).contains(options.rasterDPI) else {
            throw ConversionError.invalidOptions("rasterDPI must be between 72 and 600")
        }
        guard (1...100_000).contains(options.maximumPages) else {
            throw ConversionError.invalidOptions("maximumPages must be between 1 and 100,000")
        }
        guard (1...100_000_000).contains(options.maximumCharacters) else {
            throw ConversionError.invalidOptions("maximumCharacters must be between 1 and 100,000,000")
        }
        guard (1...48_000_000).contains(options.maximumRasterPixels) else {
            throw ConversionError.invalidOptions("maximumRasterPixels must be between 1 and 48,000,000")
        }
        guard options.maximumInputBytes > 0, options.maximumOutputBytes > 0,
              options.maximumEPUBBytes.map({ $0 > 0 }) ?? true else {
            throw ConversionError.invalidOptions("byte limits must be positive")
        }
        guard options.fullPageImageEncoding.isValid, options.regionImageEncoding.isValid else {
            throw ConversionError.invalidOptions("JPEG quality must be between 0 and 1")
        }
        if let identifier = options.packageIdentifier {
            guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  identifier.unicodeScalars.allSatisfy(isXMLCharacter) else {
                throw ConversionError.invalidOptions("package identifier must be non-blank XML text")
            }
        }
        if let date = options.modificationDate {
            // Outside this range ZIP headers would clamp and disagree with dcterms:modified.
            var utc = Calendar(identifier: .gregorian); utc.timeZone = .gmt
            guard (1980...2099).contains(utc.component(.year, from: date)) else {
                throw ConversionError.invalidOptions("modification date must fall in 1980–2099")
            }
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ConversionError.outputExists }
        guard source.resolvingSymlinksInPath() != destination.resolvingSymlinksInPath() else {
            throw ConversionError.outputExists
        }
    }
}
