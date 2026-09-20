@testable import PDFReflowLib

/// Runs test code that reads PDFKit text, makes a font, or lays out or draws text with CoreText
/// inside the library's extraction gate. PDFKit's attributed extraction aborts with the NSFont
/// exception when another thread of the process does any of these meanwhile (#21), and parallel
/// tests share their process with the library's own gated extraction. Never call the library's
/// extraction from `body`: the gate is not reentrant. `tools/check_pdfkit_gate.py` fails on such a
/// call made outside a gate.
func pdfKitGated<T, E: Error>(_ body: () throws(E) -> T) throws(E) -> T {
    // The gate throws only when the task is canceled, which no test does.
    let result: Result<T, E> = try! NativeTextReader.withExtractionLock { Result(catching: body) }
    return try result.get()
}
