import Foundation
import PDFReflowLib

@main
struct PDFReflowLibCommand {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 2, args.count <= 3 else {
            FileHandle.standardError.write(Data("Usage: pdf-reflow input.pdf output.epub [--no-ocr]\n".utf8))
            exit(args == ["--help"] ? 0 : 2)
        }
        guard args.count == 2 || args[2] == "--no-ocr" else {
            FileHandle.standardError.write(Data("Unknown option: \(args[2])\n".utf8)); exit(2)
        }
        var options = ConversionOptions()
        if args.count == 3 { options.ocr = .never }
        do {
            let report = try await PDFConverter().convert(from: URL(fileURLWithPath: args[0]),
                to: URL(fileURLWithPath: args[1]), options: options) { event in
                    let line = "\(Int(event.fractionCompleted * 100))% \(event.stage.rawValue)"
                        + (event.page.map { " page \($0)/\(event.totalPages)" } ?? "") + "\n"
                    FileHandle.standardError.write(Data(line.utf8))
                }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8)); exit(1)
        }
    }
}
