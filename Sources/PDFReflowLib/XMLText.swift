import Foundation

/// Text on its way into XML. Both the markup the writer emits and the metadata the source states
/// pass through here, so the escaping and the character filtering are defined once.

// XML 1.0 excludes control characters even when they occur in source PDF text/metadata.
func isXMLCharacter(_ scalar: Unicode.Scalar) -> Bool {
    scalar.value == 9 || scalar.value == 10 || scalar.value == 13 ||
        (scalar.value >= 0x20 && scalar.value <= 0xD7FF) ||
        (scalar.value >= 0xE000 && scalar.value <= 0xFFFD) || scalar.value >= 0x10000
}

func xml(_ string: String) -> String {
    String(String.UnicodeScalarView(string.unicodeScalars.filter(isXMLCharacter)))
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}
