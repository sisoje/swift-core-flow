import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// One resolved pick: the output label and the member-access path to emit
/// (`__v.\(path)`). Used by `PickMacro`, which reads two shapes: a bare key
/// path (`\.a`, `\.a.b`) or one renamed via the `=>` operator
/// (`\.a => "label"`).
struct KeyPathPick {
    let label: String
    let path: String
}

/// Parses a bare key path or one renamed via `=>`. `context` prefixes any
/// diagnostic message (e.g. `"#pick group 'from: store'"`).
func parseKeyPathPick(_ expr: ExprSyntax, context: String) throws -> KeyPathPick {
    if let infix = expr.as(InfixOperatorExprSyntax.self),
       let op = infix.operator.as(BinaryOperatorExprSyntax.self),
       op.operator.text == "=>"
    {
        guard let label = literalString(infix.rightOperand) else {
            throw MacroError(
                "\(context): the rename after '=>' must be a plain string literal, "
                + "got '\(infix.rightOperand.trimmedDescription)'")
        }
        let bare = try parseBareKeyPath(infix.leftOperand, context: context)
        return KeyPathPick(label: label, path: bare.path)
    }
    return try parseBareKeyPath(expr, context: context)
}

private func parseBareKeyPath(_ expr: ExprSyntax, context: String) throws -> KeyPathPick {
    guard let kp = expr.as(KeyPathExprSyntax.self) else {
        throw MacroError(
            "\(context): expected a key path like \\.field (optionally `=> \"rename\"`), "
            + "got '\(expr.trimmedDescription)'")
    }
    let names = kp.components.compactMap {
        $0.component.as(KeyPathPropertyComponentSyntax.self)?.declName.baseName.text
    }
    guard !names.isEmpty else {
        throw MacroError("\(context): unsupported key path '\(kp.trimmedDescription)'")
    }
    return KeyPathPick(label: names.last!, path: names.joined(separator: "."))
}

/// A compile error naming the duplicate output label, with a Fix-It that
/// renames the *duplicate* occurrence via `=>` (or replaces an existing
/// `=>` rename with a fresh one, if it already had one).
func duplicateLabelDiagnostic(
    macroName: String,
    diagnosticDomain: String,
    label: String,
    duplicateExpr: ExprSyntax
) -> Diagnostic {
    let messageID = MessageID(domain: diagnosticDomain, id: "duplicateLabel")
    let suggested = "\(label)2"

    let renamedExpr: ExprSyntax
    if let infix = duplicateExpr.as(InfixOperatorExprSyntax.self),
       infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "=>"
    {
        renamedExpr = "\(infix.leftOperand.trimmed) => \"\(raw: suggested)\""
    } else {
        renamedExpr = "\(duplicateExpr.trimmed) => \"\(raw: suggested)\""
    }

    return Diagnostic(
        node: Syntax(duplicateExpr),
        message: SimpleDiagnosticMessage(
            message: "\(macroName): duplicate field label '\(label)' — rename this pick",
            diagnosticID: messageID,
            severity: .error
        ),
        fixIts: [
            FixIt(
                message: SimpleDiagnosticMessage(
                    message: "rename to \"\(suggested)\"",
                    diagnosticID: messageID,
                    severity: .error
                ),
                changes: [
                    FixIt.Change.replace(
                        oldNode: Syntax(duplicateExpr),
                        newNode: Syntax(renamedExpr)
                    )
                ]
            )
        ]
    )
}
