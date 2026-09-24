import Foundation

/// One source-proven mathematical expression and the image a reader can use when MathML is
/// unavailable. Recognition supplies these nodes only after checking the source glyphs (#206).
struct MathExpression: Sendable, Equatable {
    indirect enum Node: Sendable, Equatable {
        case number(String)
        case identifier(String)
        case `operator`(String)
        case row([Node])
        case fraction(Node, Node, display: Bool = false)
        case superscript(Node, Node)
        case `subscript`(Node, Node)
        case squareRoot(Node)
    }

    var label: String?
    var node: Node
    var fallbackAssetID: String

    var linearText: String { Self.linear(node) }

    private static func linear(_ node: Node) -> String {
        switch node {
        case let .number(value), let .identifier(value), let .operator(value): return value
        case let .row(nodes):
            var text = ""
            for (index, child) in nodes.enumerated() {
                if case let .operator(symbol) = child, !"()".contains(symbol), index > 0,
                   !opensOperand(nodes[index - 1]) {
                    text += " \(symbol) "
                } else {
                    text += linear(child)
                }
            }
            return text
        case let .fraction(numerator, denominator, _):
            return grouped(numerator) + "/" + grouped(denominator)
        case let .superscript(base, script): return grouped(base) + "^" + grouped(script)
        case let .subscript(base, script): return grouped(base) + "_" + grouped(script)
        case let .squareRoot(radicand): return "√(" + linear(radicand) + ")"
        }
    }

    private static func opensOperand(_ node: Node) -> Bool {
        if case let .operator(symbol) = node { return symbol != ")" }
        return false
    }

    private static func grouped(_ node: Node) -> String {
        switch node {
        case .number, .identifier: return linear(node)
        case let .row(nodes):
            if case .operator("(")? = nodes.first, case .operator(")")? = nodes.last { return linear(node) }
            return "(" + linear(node) + ")"
        default: return "(" + linear(node) + ")"
        }
    }
}
