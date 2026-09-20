import CoreGraphics
import Foundation

/// What a content-stream reader does with the events one `ContentStreamWalk` raises. The driver
/// owns the graphics-state stack, the current transformation and text matrices, the text-object
/// state and the operation budget; a visitor keeps only the state its evidence needs. Every hook
/// has a default that does nothing.
protocol ContentStreamVisitor: AnyObject {
    /// `q`, after the driver pushed its own state: push whatever else the visitor tracks.
    func saveState()
    /// `Q`, after the driver popped its own state.
    func restoreState()
    /// `BT` and `ET`, after the driver reset the text matrix and cursor.
    func beginText(_ walk: ContentStreamWalk)
    func endText(_ walk: ContentStreamWalk)
    /// `Tf`, with the font resource the content stream names (nil when it has none).
    func selectFont(name: String, size: CGFloat, resource: CGPDFObjectRef?, walk: ContentStreamWalk)
    /// A text-show operator with its operands in order. Called before the driver clears
    /// `positioned`, so `walk.positioned` says whether a positioning operator preceded it.
    func show(_ arguments: [ContentStreamWalk.ShowArgument], walk: ContentStreamWalk)
    /// Any operator the visitor registered in `ContentStreamWalk.Options.operators`. The
    /// visitor pops its own operands.
    func handle(_ op: String, scanner: CGPDFScannerRef, walk: ContentStreamWalk)
}

extension ContentStreamVisitor {
    func saveState() {}
    func restoreState() {}
    func beginText(_ walk: ContentStreamWalk) {}
    func endText(_ walk: ContentStreamWalk) {}
    func selectFont(name: String, size: CGFloat, resource: CGPDFObjectRef?, walk: ContentStreamWalk) {}
    func show(_ arguments: [ContentStreamWalk.ShowArgument], walk: ContentStreamWalk) {}
    func handle(_ op: String, scanner: CGPDFScannerRef, walk: ContentStreamWalk) {}
}

/// One bounded scan of a page's content stream that tracks the text-placement state every
/// text-anchor reader needs: `q`/`Q`/`cm`, `BT`/`ET`, `Tm`/`Td`/`TD`/`T*`/`TL`, `Tf`, and the
/// show operators. The scan stops at the operation budget or on cancellation, and a scan that
/// ends inside a text object or with unbalanced state is not a successful scan. Readers differ
/// only in `Options`; the drift between hand-written scanners (one without a cancellation
/// check, three sets of limits) is what this replaces.
final class ContentStreamWalk {
    enum MoveAndShow {
        /// `'` and `"` are not registered; the reader never sees them.
        case ignore
        /// `'` and `"` disqualify the scan.
        case invalidate
        /// `'` and `"` move to the next line and show, like `T*` then `Tj`.
        case show
    }

    struct Options {
        /// Operators beyond the driver's own that the visitor handles; each is registered,
        /// counted against the budget and forwarded to `handle`.
        var operators: Set<String> = []
        var maximumOperations = 100_000
        var maximumSavedStates = 128
        /// `q`, `Q` and `cm` disqualify the scan inside a text object.
        var refusesStateChangesInText = false
        /// A nested `BT`, a stray `ET`, or `Tm`/`Td`/`TD`/`T*` outside a text object disqualify
        /// the scan. Lenient readers tolerate them.
        var strictTextObjects = true
        /// `BT` leaves the cursor positioned at the text-space origin.
        var beginTextPositions = true
        /// Whether `Tf` is registered and reported through `selectFont`.
        var selectsFonts = false
        /// A `TJ` array with more elements than this disqualifies the scan; nil for no cap.
        var maximumShowElements: Int? = nil
        var moveAndShow: MoveAndShow = .ignore
        /// How many Form XObjects deep `descend` will follow a `Do`. Zero follows none.
        var maximumFormDepth = 0
    }

    enum ShowArgument {
        case string(CGPDFStringRef)
        case adjustment(CGFloat)
        /// An array element that is neither a string nor a finite number.
        case other
    }

    let options: Options
    private unowned let visitor: any ContentStreamVisitor
    private(set) var matrix = CGAffineTransform.identity
    private(set) var lineMatrix = CGAffineTransform.identity
    private(set) var leading: CGFloat = 0
    private(set) var inText = false
    /// A positioning operator has run since the last show (or `BT`, where the reader says so).
    private(set) var positioned = false
    private(set) var operations = 0
    private(set) var saved: [(CGAffineTransform, CGFloat)] = []
    /// How many Form XObjects deep this walk currently is; zero in the page's own stream.
    private(set) var formDepth = 0
    /// The operator table driving this walk, kept so a form's stream is scanned with the same
    /// callbacks, the same budget and the same visitor.
    private var table: CGPDFOperatorTableRef?
    /// Set by the driver or the visitor; stops the scan at the next operator.
    var invalid = false

    /// The text-space-to-page transform of the current show: the text matrix under the CTM.
    var textTransform: CGAffineTransform { lineMatrix.concatenating(matrix) }

    private init(options: Options, visitor: any ContentStreamVisitor) {
        self.options = options
        self.visitor = visitor
    }

    /// Scans `page`'s own content stream, driving `visitor`. True when the whole stream was
    /// scanned within budget, nothing disqualified it, and it ended outside any text object with
    /// its state stack balanced.
    static func scan(_ page: CGPDFPage, options: Options, visitor: any ContentStreamVisitor) -> Bool {
        guard let table = CGPDFOperatorTableCreate() else { return false }
        defer { CGPDFOperatorTableRelease(table) }
        var operators = coreOperators
        if options.selectsFonts { operators.insert("Tf") }
        if options.moveAndShow != .ignore { operators.formUnion(["'", "\""]) }
        operators.formUnion(options.operators)
        for op in operators {
            guard let callback = callbacks[op] else { preconditionFailure("no callback for operator \(op)") }
            CGPDFOperatorTableSetCallback(table, op, callback)
        }
        let walk = ContentStreamWalk(options: options, visitor: visitor)
        walk.table = table
        defer { walk.table = nil }
        let stream = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(stream) }
        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(walk).toOpaque())
        defer { CGPDFScannerRelease(scanner) }
        return CGPDFScannerScan(scanner) && !walk.invalid && walk.saved.isEmpty && !walk.inText
    }

    /// Scans a Form XObject's content as part of this walk, driving the same visitor from inside
    /// `Do`. The form runs under its own `Matrix` and `resources`, and inside the implicit
    /// `q`/`Q` the operator carries, so the transformation, leading and saved-state stack the
    /// form changes do not outlive it; state the visitor keeps is the visitor's to restore.
    ///
    /// False, with the walk disqualified, when the form cannot be followed at all: nesting past
    /// `Options.maximumFormDepth`, a `Do` inside a text object, a `Matrix` that is not six finite
    /// numbers, a stream the scanner cannot read or that spends the shared operation budget, and
    /// a stream whose own `q`/`Q` or `BT`/`ET` do not balance — a form that ends inside a text
    /// object has shown text from a state this walk cannot account for.
    func descend(into form: CGPDFStreamRef, dictionary: CGPDFDictionaryRef,
                 resources: CGPDFDictionaryRef, scanner: CGPDFScannerRef) -> Bool {
        guard let table, formDepth < options.maximumFormDepth, !inText else { invalid = true; return false }
        let outerMatrix = matrix, outerSaved = saved, outerLeading = leading
        if CGPDFObjects.object(dictionary, "Matrix") != nil {
            guard let own = CGPDFObjects.matrix(dictionary, "Matrix") else { invalid = true; return false }
            matrix = own.concatenating(matrix)
        }
        saved = []
        formDepth += 1
        let content = CGPDFContentStreamCreateWithStream(form, resources, CGPDFScannerGetContentStream(scanner))
        let nested = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(self).toOpaque())
        if !CGPDFScannerScan(nested) || !saved.isEmpty || inText { invalid = true }
        CGPDFScannerRelease(nested)
        CGPDFContentStreamRelease(content)
        formDepth -= 1
        matrix = outerMatrix
        saved = outerSaved
        leading = outerLeading
        inText = false
        positioned = false
        return !invalid
    }

    /// `count` finite numbers popped from the operand stack, in operand order.
    static func numbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [CGFloat]? {
        var values = [CGFloat](repeating: 0, count: count)
        for i in values.indices.reversed() {
            var value: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &value), value.isFinite else { return nil }
            values[i] = value
        }
        return values
    }

    static func popName(_ scanner: CGPDFScannerRef) -> String? {
        var name: UnsafePointer<CChar>?
        guard CGPDFScannerPopName(scanner, &name), let name else { return nil }
        return String(cString: name)
    }

    /// Counts one operator against the budget; false (and the scan stopped) when the budget is
    /// spent, the task is canceled, or something already disqualified the scan.
    func accept(_ scanner: CGPDFScannerRef) -> Bool {
        operations += 1
        if operations > options.maximumOperations || Task.isCancelled { invalid = true }
        if invalid { CGPDFScannerStop(scanner) }
        return !invalid
    }

    // MARK: - Operators

    private static let coreOperators: Set<String> = ["q", "Q", "cm", "BT", "ET", "Tm", "Td", "TD", "T*", "TL", "Tj", "TJ"]

    private static func walk(_ info: UnsafeMutableRawPointer?) -> ContentStreamWalk {
        Unmanaged<ContentStreamWalk>.fromOpaque(info!).takeUnretainedValue()
    }

    private func save(_ scanner: CGPDFScannerRef) {
        guard accept(scanner), !(options.refusesStateChangesInText && inText),
              saved.count < options.maximumSavedStates else { invalid = true; return }
        saved.append((matrix, leading))
        visitor.saveState()
    }

    private func restore(_ scanner: CGPDFScannerRef) {
        guard accept(scanner), !(options.refusesStateChangesInText && inText),
              let state = saved.popLast() else { invalid = true; return }
        (matrix, leading) = state
        visitor.restoreState()
    }

    private func concatenate(_ scanner: CGPDFScannerRef) {
        guard accept(scanner), !(options.refusesStateChangesInText && inText),
              let n = Self.numbers(scanner, 6) else { invalid = true; return }
        matrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5]).concatenating(matrix)
    }

    private func beginText(_ scanner: CGPDFScannerRef) {
        guard accept(scanner) else { return }
        if options.strictTextObjects, inText { invalid = true; return }
        inText = true
        lineMatrix = .identity
        positioned = options.beginTextPositions
        visitor.beginText(self)
    }

    private func endText(_ scanner: CGPDFScannerRef) {
        guard accept(scanner) else { return }
        if options.strictTextObjects, !inText { invalid = true; return }
        inText = false
        positioned = false
        visitor.endText(self)
    }

    /// True when a positioning operator may run here.
    private func positioning(_ scanner: CGPDFScannerRef) -> Bool {
        guard accept(scanner) else { return false }
        if options.strictTextObjects, !inText { invalid = true; return false }
        return true
    }

    private func setTextMatrix(_ scanner: CGPDFScannerRef) {
        guard positioning(scanner), let n = Self.numbers(scanner, 6) else { invalid = true; return }
        lineMatrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
        positioned = true
    }

    private func move(_ scanner: CGPDFScannerRef, setsLeading: Bool) {
        // The operands are popped before the text-object check so a stray `Td` outside `BT`
        // still consumes them, as every hand-written scanner did.
        guard accept(scanner), let n = Self.numbers(scanner, 2) else { invalid = true; return }
        if options.strictTextObjects, !inText { invalid = true; return }
        if setsLeading { leading = -n[1] }
        lineMatrix = lineMatrix.translatedBy(x: n[0], y: n[1])
        positioned = true
    }

    private func nextLine(_ scanner: CGPDFScannerRef) {
        guard positioning(scanner) else { return }
        lineMatrix = lineMatrix.translatedBy(x: 0, y: -leading)
        positioned = true
    }

    private func setLeading(_ scanner: CGPDFScannerRef) {
        guard accept(scanner), let n = Self.numbers(scanner, 1) else { invalid = true; return }
        leading = n[0]
    }

    private func selectFont(_ scanner: CGPDFScannerRef) {
        guard accept(scanner), let n = Self.numbers(scanner, 1), let name = Self.popName(scanner) else {
            invalid = true; return
        }
        let resource = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "Font", name)
        visitor.selectFont(name: name, size: n[0], resource: resource, walk: self)
    }

    private func show(_ scanner: CGPDFScannerRef, array: Bool) {
        guard accept(scanner) else { return }
        var arguments: [ShowArgument] = []
        if array {
            var values: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &values), let values else { invalid = true; return }
            let count = CGPDFArrayGetCount(values)
            if let maximum = options.maximumShowElements, count > maximum { invalid = true; return }
            for i in 0..<count {
                var string: CGPDFStringRef?
                var number: CGPDFReal = 0
                if CGPDFArrayGetString(values, i, &string), let string { arguments.append(.string(string)) }
                else if CGPDFArrayGetNumber(values, i, &number), number.isFinite { arguments.append(.adjustment(number)) }
                else { arguments.append(.other) }
            }
        } else {
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string else { invalid = true; return }
            arguments = [.string(string)]
        }
        visitor.show(arguments, walk: self)
        positioned = false
    }

    private func moveAndShow(_ scanner: CGPDFScannerRef, spacing: Bool) {
        switch options.moveAndShow {
        case .ignore:
            return
        case .invalidate:
            invalid = true
        case .show:
            // The line move does not count as its own operator; the show does.
            if options.strictTextObjects, !inText { invalid = true; return }
            lineMatrix = lineMatrix.translatedBy(x: 0, y: -leading)
            positioned = true
            show(scanner, array: false)
            // Word and character spacing precede the string; they do not change the origin.
            if spacing, Self.numbers(scanner, 2) == nil { invalid = true }
        }
    }

    private func forward(_ op: String, _ scanner: CGPDFScannerRef) {
        guard accept(scanner) else { return }
        visitor.handle(op, scanner: scanner, walk: self)
    }

    /// One C callback per operator the driver knows. Each forwards to the walk in `info`.
    private static let callbacks: [String: CGPDFOperatorCallback] = [
        "q": { scanner, info in walk(info).save(scanner) },
        "Q": { scanner, info in walk(info).restore(scanner) },
        "cm": { scanner, info in walk(info).concatenate(scanner) },
        "BT": { scanner, info in walk(info).beginText(scanner) },
        "ET": { scanner, info in walk(info).endText(scanner) },
        "Tm": { scanner, info in walk(info).setTextMatrix(scanner) },
        "Td": { scanner, info in walk(info).move(scanner, setsLeading: false) },
        "TD": { scanner, info in walk(info).move(scanner, setsLeading: true) },
        "T*": { scanner, info in walk(info).nextLine(scanner) },
        "TL": { scanner, info in walk(info).setLeading(scanner) },
        "Tf": { scanner, info in walk(info).selectFont(scanner) },
        "Tj": { scanner, info in walk(info).show(scanner, array: false) },
        "TJ": { scanner, info in walk(info).show(scanner, array: true) },
        "'": { scanner, info in walk(info).moveAndShow(scanner, spacing: false) },
        "\"": { scanner, info in walk(info).moveAndShow(scanner, spacing: true) },
        "Tc": { scanner, info in walk(info).forward("Tc", scanner) },
        "Tw": { scanner, info in walk(info).forward("Tw", scanner) },
        "Tz": { scanner, info in walk(info).forward("Tz", scanner) },
        "Ts": { scanner, info in walk(info).forward("Ts", scanner) },
        "Tr": { scanner, info in walk(info).forward("Tr", scanner) },
        "gs": { scanner, info in walk(info).forward("gs", scanner) },
        "BI": { scanner, info in walk(info).forward("BI", scanner) },
        "Do": { scanner, info in walk(info).forward("Do", scanner) },
        "BDC": { scanner, info in walk(info).forward("BDC", scanner) },
        "BMC": { scanner, info in walk(info).forward("BMC", scanner) },
        "EMC": { scanner, info in walk(info).forward("EMC", scanner) },
    ]
}
