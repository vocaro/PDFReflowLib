import Foundation

/// A fresh-process probe for the value-only index; deliberately excludes PDFKit and rasterization.
@main struct InspectStructure {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let index = try StructureTreeReader.read(URL(fileURLWithPath: CommandLine.arguments[1]))
        let references = index.pages.values.reduce(0) { $0 + $1.count }
        print("Indexed \(references) references on \(index.pages.count) pages.")
        guard references > 0 else { throw CocoaError(.fileReadCorruptFile) }
    }
}
