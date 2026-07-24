import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `#pick(from: store, \.expenses, \.limit, from: actions, \.alerts)` →
///   `{ let __v0 = store; let __v1 = actions;
///      return (expenses: __v0.expenses, limit: __v0.limit, alerts: __v1.alerts) }()`
///
/// The ONE implementation behind every arity of `#pick`, selected by Swift's
/// own overload resolution from argument count — nothing this macro inspects
/// itself. Rules and their verification: the public overloads' doc in
/// `TuplePicker.swift`. Each `from:` starts a group; a repeated source value
/// is bound once (`__v0`, …), in order of first appearance, not re-evaluated
/// per group.
public struct PickMacro: ExpressionMacro {

    private static let diagnosticDomain = "TuplePicker.pick"

    private struct Group {
        let valueText: String
        let picks: [(expr: ExprSyntax, pick: KeyPathPick)]
    }

    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let args = Array(node.arguments)
        guard !args.isEmpty, args[0].label?.text == "from" else {
            throw MacroError(
                "#pick: every source starts with 'from:', e.g. "
                    + "#pick(from: store, \\.a, \\.b) or #pick(from: store, \\.a, from: actions, \\.b)"
            )
        }

        var groups: [Group] = []
        var valueText: String = args[0].expression.trimmedDescription
        var picks: [(expr: ExprSyntax, pick: KeyPathPick)] = []

        func flushGroup() throws {
            guard !picks.isEmpty else {
                throw MacroError("#pick: group 'from: \(valueText)' has no picks")
            }
            groups.append(Group(valueText: valueText, picks: picks))
            picks = []
        }

        for arg in args.dropFirst() {
            if arg.label?.text == "from" {
                try flushGroup()
                valueText = arg.expression.trimmedDescription
            } else {
                let context = "#pick group 'from: \(valueText)'"
                picks.append(
                    (arg.expression, try parseKeyPathPick(arg.expression, context: context)))
            }
        }
        try flushGroup()

        // Bind each distinct group value once, in order of first appearance;
        // a value repeated across groups reuses its existing __vN.
        var varNameByValue: [String: String] = [:]
        var bindings: [String] = []
        var fields: [(expr: ExprSyntax, varName: String, pick: KeyPathPick)] = []

        for group in groups {
            let varName: String
            if let existing = varNameByValue[group.valueText] {
                varName = existing
            } else {
                varName = "__v\(bindings.count)"
                varNameByValue[group.valueText] = varName
                bindings.append("let \(varName) = \(group.valueText)")
            }
            for (expr, pick) in group.picks {
                fields.append((expr, varName, pick))
            }
        }

        var seen: Set<String> = []
        var hasDuplicate = false
        for field in fields {
            if seen.contains(field.pick.label) {
                hasDuplicate = true
                context.diagnose(
                    duplicateLabelDiagnostic(
                        macroName: "#pick",
                        diagnosticDomain: diagnosticDomain,
                        label: field.pick.label,
                        duplicateExpr: field.expr
                    )
                )
            } else {
                seen.insert(field.pick.label)
            }
        }
        guard !hasDuplicate else {
            return "{ fatalError(\"#pick: duplicate field labels\") }()"
        }

        let prelude = bindings.joined(separator: "; ")
        if fields.count == 1 {
            let only = fields[0]
            return "{ \(raw: prelude); return \(raw: only.varName).\(raw: only.pick.path) }()"
        }
        let tupleBody =
            fields
            .map { "\($0.pick.label): \($0.varName).\($0.pick.path)" }
            .joined(separator: ", ")
        return "{ \(raw: prelude); return (\(raw: tupleBody)) }()"
    }
}
