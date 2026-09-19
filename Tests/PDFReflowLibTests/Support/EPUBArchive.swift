import Foundation
import Testing
import ZIPFoundation

/// Reading a written EPUB back in tests: one place for the entry-extraction idiom that thirteen
/// test files used to spell out.
extension Archive {
    /// The bytes of one archive entry, or a recorded failure when the entry is missing.
    func entryData(_ path: String) throws -> Data {
        let entry = try #require(self[path], "no entry \(path)")
        var data = Data()
        _ = try extract(entry) { data += $0 }
        return data
    }

    func entryText(_ path: String) throws -> String {
        String(decoding: try entryData(path), as: UTF8.self)
    }

    /// The XHTML of spine document `number`.
    func chapter(_ number: Int = 1) throws -> String {
        try entryText("EPUB/chapter-\(number).xhtml")
    }
}
