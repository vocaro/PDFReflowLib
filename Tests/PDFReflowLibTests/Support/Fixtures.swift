import Foundation
#if os(macOS)
import AppKit
/// The platform font class tests use to build attributed strings; made under the PDFKit gate.
typealias PlatformFont = NSFont
#else
import UIKit
typealias PlatformFont = UIFont
#endif

/// A file under the test target's `fixtures/` resource directory.
func fixtureURL(_ name: String) -> URL {
    Bundle.module.resourceURL!.appendingPathComponent("fixtures/\(name)")
}
