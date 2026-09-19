import CoreGraphics
import Foundation

/// Typed accessors over Core Graphics PDF objects, and the page-tree walks every reader needs.
/// Nothing here retains a Core Graphics object; callers use the results inside the pool that
/// owns the page.
enum CGPDFObjects {
    static func object(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFObjectRef? {
        var value: CGPDFObjectRef?
        return CGPDFDictionaryGetObject(dict, key, &value) ? value : nil
    }
    static func dictionary(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFDictionaryRef? {
        var value: CGPDFDictionaryRef?
        return CGPDFDictionaryGetDictionary(dict, key, &value) ? value : nil
    }
    static func array(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFArrayRef? {
        var value: CGPDFArrayRef?
        return CGPDFDictionaryGetArray(dict, key, &value) ? value : nil
    }
    static func stream(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFStreamRef? {
        var value: CGPDFStreamRef?
        return CGPDFDictionaryGetStream(dict, key, &value) ? value : nil
    }
    static func integer(_ dict: CGPDFDictionaryRef, _ key: String) -> Int? {
        var value: CGPDFInteger = 0
        return CGPDFDictionaryGetInteger(dict, key, &value) ? value : nil
    }
    static func name(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict, key, &value), let value else { return nil }
        return String(cString: value)
    }
    static func text(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dict, key, &value), let value else { return nil }
        return CGPDFStringCopyTextString(value) as String?
    }
    /// The dictionary an object holds directly, or the dictionary of the stream it holds.
    static func dictionary(of object: CGPDFObjectRef) -> CGPDFDictionaryRef? {
        var dict: CGPDFDictionaryRef?
        if CGPDFObjectGetValue(object, .dictionary, &dict), let dict { return dict }
        var stream: CGPDFStreamRef?
        if CGPDFObjectGetValue(object, .stream, &stream), let stream { return CGPDFStreamGetDictionary(stream) }
        return nil
    }
    static func stream(of object: CGPDFObjectRef) -> CGPDFStreamRef? {
        var stream: CGPDFStreamRef?
        return CGPDFObjectGetValue(object, .stream, &stream) ? stream : nil
    }

    /// `count` finite numbers from an array, or nil when any entry is missing or not finite.
    static func numbers(_ array: CGPDFArrayRef, count: Int) -> [CGFloat]? {
        guard CGPDFArrayGetCount(array) == count else { return nil }
        var values = [CGFloat](repeating: 0, count: count)
        for index in 0..<count {
            var value: CGPDFReal = 0
            guard CGPDFArrayGetNumber(array, index, &value), value.isFinite else { return nil }
            values[index] = value
        }
        return values
    }

    /// A rectangle entry (`BBox`, `MediaBox`), standardized: PDF rectangles can name either pair
    /// of opposite corners (InDesign uses both orders).
    static func rectangle(_ dict: CGPDFDictionaryRef, _ key: String) -> CGRect? {
        guard let array = array(dict, key), let n = numbers(array, count: 4) else { return nil }
        let rect = CGRect(x: n[0], y: n[1], width: n[2] - n[0], height: n[3] - n[1]).standardized
        return rect.isFinite ? rect : nil
    }

    /// A matrix entry (`Matrix`, `FontMatrix`).
    static func matrix(_ dict: CGPDFDictionaryRef, _ key: String) -> CGAffineTransform? {
        guard let array = array(dict, key), let n = numbers(array, count: 6) else { return nil }
        return CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
    }

    /// A stream entry's data when it is stored uncompressed (`.raw`); nil for encoded data.
    static func rawData(_ dict: CGPDFDictionaryRef, _ key: String) -> Data? {
        guard let stream = stream(dict, key) else { return nil }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format), format == .raw else { return nil }
        return data as Data
    }

    /// The page's own `Resources`, or the nearest ancestor's: resources are inheritable through
    /// the page tree. The walk is bounded to 64 ancestors.
    static func inheritedResources(of page: CGPDFPage) -> CGPDFDictionaryRef? {
        var node: CGPDFDictionaryRef? = page.dictionary
        for _ in 0..<64 {
            guard let current = node else { return nil }
            if let resources = dictionary(current, "Resources") { return resources }
            node = dictionary(current, "Parent")
        }
        return nil
    }

    /// Every font dictionary a resource dictionary's `Font` entry holds, in the order Core
    /// Graphics enumerates them; empty when there is no `Font` entry.
    static func fonts(in resources: CGPDFDictionaryRef) -> [CGPDFDictionaryRef] {
        guard let fonts = dictionary(resources, "Font") else { return [] }
        var result: [CGPDFDictionaryRef] = []
        CGPDFDictionaryApplyBlock(fonts, { _, object, _ in
            var dict: CGPDFDictionaryRef?
            if CGPDFObjectGetValue(object, .dictionary, &dict), let dict { result.append(dict) }
            return true
        }, nil)
        return result
    }
}
