import CoreGraphics
import Foundation

/// The original bytes of an image a page places, for the crops that are exactly that image (#251).
///
/// Every image in an output book used to be a re-render: the page was redrawn at `rasterDPI` and
/// re-compressed. Where a figure *is* one embedded JPEG — a photograph, a scanned plate — the
/// original stream is both higher fidelity than a 180 DPI redraw and usually smaller, and the
/// ceiling on quality was the render rather than the source, whatever `rasterDPI` was set to.
///
/// The safe set is deliberately narrow. Only `DCTDecode` is extracted, because only it is already
/// a file a reader can open: a `FlateDecode` image's stream is raw samples, so writing it would be
/// a re-encode and not an extraction, and `JPXDecode`, `CCITTFaxDecode` and `JBIG2Decode` are not
/// image files either. Masks, stencils, `/Decode` arrays, colour spaces other than device RGB and
/// gray, rotated or skewed placements, and a crop that shows anything besides the one image all
/// fall back to the render they always had.
enum EmbeddedImageReader {
    /// One image XObject as a page places it. `stream` belongs to the open page and must not
    /// outlive it.
    struct Placement {
        var rect: CGRect
        var stream: CGPDFStreamRef
        /// Placed without rotation or skew, so the stream's pixels stand as the page draws them.
        var upright: Bool
    }

    /// Bounds on one page's walk: the same order as the graphics reader's own caps.
    static let maximumImages = 10_000
    static let maximumDepth = 12
    /// How much of each rectangle the other must cover for the crop to be that image and nothing
    /// else. A crop is padded by a point or two, and a placement lands on fractional coordinates.
    static let coverage = 0.98

    /// Every image XObject `page` places, in the order it places them. An empty result means the
    /// page places none, or that the walk could not be trusted to have seen them all.
    static func placements(_ page: CGPDFPage) -> [Placement] {
        guard let table = CGPDFOperatorTableCreate() else { return [] }
        defer { CGPDFOperatorTableRelease(table) }
        let state = State()
        state.table = table
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            let s = Self.state(info)
            guard s.saved.count < 128 else { s.failed = true; return }
            s.saved.append(s.matrix)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            let s = Self.state(info)
            if let matrix = s.saved.popLast() { s.matrix = matrix } else { s.failed = true }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let s = Self.state(info)
            var values = [CGPDFReal](repeating: 0, count: 6)
            for index in (0..<6).reversed() {
                guard CGPDFScannerPopNumber(scanner, &values[index]) else { s.failed = true; return }
            }
            let concatenated = CGAffineTransform(a: values[0], b: values[1], c: values[2],
                                                 d: values[3], tx: values[4], ty: values[5])
            s.matrix = concatenated.concatenating(s.matrix)
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let s = Self.state(info)
            var name: UnsafePointer<CChar>?
            let parent = CGPDFScannerGetContentStream(scanner)
            guard CGPDFScannerPopName(scanner, &name), let name,
                  let resource = CGPDFContentStreamGetResource(parent, "XObject", name) else {
                s.failed = true; return
            }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(resource, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream) else { s.failed = true; return }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else {
                s.failed = true; return
            }
            switch String(cString: subtype) {
            case "Image":
                guard s.placements.count < Self.maximumImages else { s.failed = true; return }
                let rect = CGRect(x: 0, y: 0, width: 1, height: 1).applying(s.matrix)
                guard rect.isFinite else { s.failed = true; return }
                // A placement that rotates or skews the image draws pixels the stream does not
                // hold in that order, so its bytes are not what the page shows.
                let upright = abs(s.matrix.b) < 1e-6 && abs(s.matrix.c) < 1e-6
                s.placements.append(Placement(rect: rect, stream: stream, upright: upright))
            case "Form":
                Self.descend(stream, dictionary: dictionary, parent: parent, state: s)
            default: s.failed = true
            }
        }
        if let dictionary = page.dictionary {
            CGPDFDictionaryGetDictionary(dictionary, "Resources", &state.resources)
        }
        let content = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(content) }
        Self.scan(content, state: state)
        return state.failed ? [] : state.placements
    }

    /// What the page says the stream's samples mean, where that is something a JPEG file can
    /// carry on its own.
    enum ColorSpace: Equatable {
        /// A device space: the JPEG's own components say everything.
        case device(components: Int)
        /// An ICC-based space, whose profile travels with the extracted file so that the colours
        /// are the ones the page draws and not the reader's guess.
        case iccBased(components: Int, profile: Data)

        var components: Int {
            switch self {
            case let .device(components), let .iccBased(components, _): components
            }
        }
    }

    /// The bytes to write for `rect`, or nil where the page's own rendering must stand.
    static func extractableJPEG(for rect: CGRect, among placements: [Placement],
                                maximumBytes: Int) -> Data? {
        guard rect.isFinite, rect.width > 0, rect.height > 0, maximumBytes > 0 else { return nil }
        let area = rect.width * rect.height
        let touching = placements.filter { !$0.rect.intersection(rect).isNull && !$0.rect.intersection(rect).isEmpty }
        // The crop must show one image and nothing else of the page's pictures.
        guard touching.count == 1, let placement = touching.first, placement.upright,
              placement.rect.width > 0, placement.rect.height > 0 else { return nil }
        let overlap = placement.rect.intersection(rect)
        let shared = overlap.width * overlap.height
        guard shared >= area * coverage,
              shared >= placement.rect.width * placement.rect.height * coverage else { return nil }
        guard let dictionary = CGPDFStreamGetDictionary(placement.stream),
              let space = writableJPEGColorSpace(dictionary) else { return nil }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(placement.stream, &format) as Data?,
              format == .jpegEncoded, !data.isEmpty else { return nil }
        // The dictionary describes the samples and the JPEG header describes them again. They
        // must agree, or the file a reader opens is not the picture the page drew — which is how
        // a CMYK or Adobe-inverted stream shows itself.
        guard let header = jpegFrame(data), header.components == space.components,
              header.width == size(dictionary, "Width"), header.height == size(dictionary, "Height") else {
            return nil
        }
        let written: Data
        if case let .iccBased(_, profile) = space, !profile.isEmpty, !hasICCProfile(data) {
            guard let embedded = insertingICCProfile(profile, into: data) else { return nil }
            written = embedded
        } else {
            written = data
        }
        return written.count <= maximumBytes ? written : nil
    }

    /// The colour space of a stream that can otherwise be written as a JPEG file, or nil.
    /// Everything unlisted falls back rather than growing a special case.
    static func writableJPEGColorSpace(_ dictionary: CGPDFDictionaryRef) -> ColorSpace? {
        guard name(dictionary, "Filter") == "DCTDecode" else { return nil }
        var object: CGPDFObjectRef?
        // A stencil, a soft mask or a colour key makes the stream's pixels only part of the
        // picture; a decode array reinterprets them.
        guard !CGPDFDictionaryGetObject(dictionary, "SMask", &object),
              !CGPDFDictionaryGetObject(dictionary, "Mask", &object),
              !CGPDFDictionaryGetObject(dictionary, "Decode", &object) else { return nil }
        var stencil: CGPDFBoolean = 0
        if CGPDFDictionaryGetBoolean(dictionary, "ImageMask", &stencil), stencil != 0 { return nil }
        var depth: CGPDFInteger = 0
        guard CGPDFDictionaryGetInteger(dictionary, "BitsPerComponent", &depth), depth == 8,
              size(dictionary, "Width") > 0, size(dictionary, "Height") > 0 else { return nil }
        if let space = name(dictionary, "ColorSpace") {
            switch space {
            case "DeviceRGB": return .device(components: 3)
            case "DeviceGray": return .device(components: 1)
            // CMYK, and any space that needs a lookup, fall back.
            default: return nil
            }
        }
        // `[/ICCBased stream]`, which is what most producers write — every DCTDecode image in the
        // magazine, NCA5 and the CDC report. The profile is carried into the file below.
        var array: CGPDFArrayRef?
        var family: UnsafePointer<CChar>?
        var profileStream: CGPDFStreamRef?
        guard CGPDFDictionaryGetArray(dictionary, "ColorSpace", &array), let array,
              CGPDFArrayGetCount(array) == 2, CGPDFArrayGetName(array, 0, &family), let family,
              String(cString: family) == "ICCBased",
              CGPDFArrayGetStream(array, 1, &profileStream), let profileStream,
              let profileDictionary = CGPDFStreamGetDictionary(profileStream) else { return nil }
        var components: CGPDFInteger = 0
        guard CGPDFDictionaryGetInteger(profileDictionary, "N", &components),
              components == 3 || components == 1 else { return nil }
        var format = CGPDFDataFormat.raw
        let profile = (CGPDFStreamCopyData(profileStream, &format) as Data?) ?? Data()
        // A profile is a few kilobytes; one that is not is not carried, and neither is the image.
        guard format == .raw, profile.count <= maximumProfileBytes else { return nil }
        return .iccBased(components: Int(components), profile: profile)
    }

    /// The largest ICC profile carried into an extracted file. Real profiles are a few kilobytes;
    /// sRGB is under 3,200 bytes.
    static let maximumProfileBytes = 1 << 20

    /// The dimensions and component count a JPEG's own frame header states.
    static func jpegFrame(_ data: Data) -> (width: Int, height: Int, components: Int)? {
        guard data.count > 4, data[data.startIndex] == 0xFF, data[data.startIndex + 1] == 0xD8 else { return nil }
        var index = data.startIndex + 2
        while index + 9 < data.endIndex {
            guard data[index] == 0xFF else { index += 1; continue }
            let marker = data[index + 1]
            // Standalone markers carry no length; everything else states one.
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) { index += 2; continue }
            let length = Int(data[index + 2]) << 8 | Int(data[index + 3])
            guard length >= 2 else { return nil }
            // A start-of-frame marker, excluding the arithmetic and hierarchical variants that
            // share the range but not the layout.
            if (0xC0...0xCF).contains(marker), marker != 0xC4, marker != 0xC8, marker != 0xCC {
                guard index + 9 < data.endIndex else { return nil }
                let height = Int(data[index + 5]) << 8 | Int(data[index + 6])
                let width = Int(data[index + 7]) << 8 | Int(data[index + 8])
                return (width, height, Int(data[index + 9]))
            }
            index += 2 + length
        }
        return nil
    }

    /// Whether the file already carries an ICC profile of its own.
    static func hasICCProfile(_ data: Data) -> Bool {
        data.range(of: Data("ICC_PROFILE\0".utf8)) != nil
    }

    /// The same JPEG with `profile` written into it as APP2 segments, so a reader opening the
    /// extracted file alone sees the colours the page states. Nil where the profile needs more
    /// segments than JPEG allows.
    static func insertingICCProfile(_ profile: Data, into data: Data) -> Data? {
        let chunkSize = 65_519 - 14  // Segment payload, less the marker's own header and tag.
        let chunks = stride(from: 0, to: profile.count, by: chunkSize).map { start in
            profile[profile.index(profile.startIndex, offsetBy: start)..<profile.index(
                profile.startIndex, offsetBy: min(start + chunkSize, profile.count))]
        }
        guard !chunks.isEmpty, chunks.count <= 255 else { return nil }
        var segments = Data()
        for (number, chunk) in chunks.enumerated() {
            let length = chunk.count + 16
            segments.append(contentsOf: [0xFF, 0xE2, UInt8(length >> 8), UInt8(length & 0xFF)])
            segments.append(Data("ICC_PROFILE\0".utf8))
            segments.append(contentsOf: [UInt8(number + 1), UInt8(chunks.count)])
            segments.append(chunk)
        }
        var result = Data(data[data.startIndex..<(data.startIndex + 2)])
        result.append(segments)
        result.append(data[(data.startIndex + 2)...])
        return result
    }

    private static func size(_ dictionary: CGPDFDictionaryRef, _ key: String) -> Int {
        var value: CGPDFInteger = 0
        guard CGPDFDictionaryGetInteger(dictionary, key, &value) else { return 0 }
        return Int(value)
    }

    private static func name(_ dictionary: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, key, &value), let value else { return nil }
        return String(cString: value)
    }

    private final class State {
        var matrix = CGAffineTransform.identity
        var saved: [CGAffineTransform] = []
        var placements: [Placement] = []
        var resources: CGPDFDictionaryRef?
        var table: CGPDFOperatorTableRef?
        var depth = 0
        /// The walk saw something it could not follow, so it cannot claim to have seen every
        /// image the page places. Nothing is extracted from such a page.
        var failed = false
    }

    private static func state(_ info: UnsafeMutableRawPointer?) -> State {
        Unmanaged<State>.fromOpaque(info!).takeUnretainedValue()
    }

    private static func scan(_ content: CGPDFContentStreamRef, state: State) {
        let scanner = CGPDFScannerCreate(content, state.table!, Unmanaged.passUnretained(state).toOpaque())
        if !CGPDFScannerScan(scanner) { state.failed = true }
        CGPDFScannerRelease(scanner)
    }

    private static func descend(_ form: CGPDFStreamRef, dictionary: CGPDFDictionaryRef,
                                parent: CGPDFContentStreamRef, state s: State) {
        guard s.depth < maximumDepth else { s.failed = true; return }
        let matrix = s.matrix, saved = s.saved, resources = s.resources
        defer { s.matrix = matrix; s.saved = saved; s.resources = resources; s.depth -= 1 }
        s.depth += 1
        s.saved = []
        if CGPDFObjects.array(dictionary, "Matrix") != nil {
            guard let own = CGPDFObjects.matrix(dictionary, "Matrix") else { s.failed = true; return }
            s.matrix = own.concatenating(s.matrix)
        }
        var formResources: CGPDFDictionaryRef?
        CGPDFDictionaryGetDictionary(dictionary, "Resources", &formResources)
        guard let resolved = formResources ?? s.resources else { s.failed = true; return }
        s.resources = resolved
        let content = CGPDFContentStreamCreateWithStream(form, resolved, parent)
        defer { CGPDFContentStreamRelease(content) }
        scan(content, state: s)
    }
}
