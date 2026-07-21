import SwiftDiagnostics
import SwiftSyntax

struct MacroError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// A `Diagnostic`/`FixIt` message backed by a plain string, for macros that
/// need `context.diagnose(...)` directly (e.g. to attach a Fix-It) instead
/// of throwing a `MacroError`.
struct SimpleDiagnosticMessage: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity
}

extension SimpleDiagnosticMessage: FixItMessage {
    var fixItID: MessageID { diagnosticID }
}

/// Extracts a plain string from a simple string literal (no interpolation).
func literalString(_ expr: ExprSyntax) -> String? {
    guard let lit = expr.as(StringLiteralExprSyntax.self),
        lit.segments.count == 1,
        let seg = lit.segments.first?.as(StringSegmentSyntax.self)
    else { return nil }
    return seg.content.text
}
