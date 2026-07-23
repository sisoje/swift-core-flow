import SwiftSyntax
import SwiftSyntaxMacros

// Two per-property macros for mutation-logging test hosts. Both hardcode the
// `\.testLog` environment entry (it ships in this package) and generate their
// own `log_<name>` environment read as an explicit `Environment` stored field
// (`private let log_x = Environment(\.testLog)`) — the `@Environment` sugar is
// a swiftc crash when PEER-macro-generated (see CLAUDE.md), and SwiftUI
// installs DynamicProperties by field type, not wrapper syntax, so injection
// is identical — and there's no shared seam member to coordinate. Same shape
// requirements for both: a stored `var` with an initial value. No diagnostics:
// a skipped shape generates nothing, and the use site fails in the compiler's
// own words.

/// `@TestState private var count: Int = 0` — a drop-in `@State` that logs.
/// The property is rewritten to read/write a generated `State` storage (so it
/// stays LIVE, exactly like `@State`'s own wrappedValue), with the logging call
/// in its setter — every write logs, wherever it comes from:
/// - accessors: an init accessor funneling the inline default into the storage,
///   `get { count_storage.wrappedValue }`, and a logging `nonmutating set`.
/// - `private let count_storage: State<Int>` — initialized via the init
///   accessor, installed by SwiftUI as a DynamicProperty by type.
/// - `private let log_count = Environment(\.testLog)`
/// - `` `$count` ``: `Binding<Int>` routed through the property itself, so
///   binding writes log through the same single setter.
///
/// Works on a `var` of ANY type, function types included — a `var` closure
/// means someone wants to mutate the closure itself, and the binding is exactly
/// that. Type comes from the annotation or the shared three-literal inference
/// (`= false` / `= 0` / `= "x"`).
public enum TestStateMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let (name, _, _) = stateProperty(declaration) else { return [] }
        return [
            """
            @storageRestrictions(initializes: \(raw: name)_storage)
            init(initialValue) {
                \(raw: name)_storage = State(wrappedValue: initialValue)
            }
            """,
            """
            get {
                \(raw: name)_storage.wrappedValue
            }
            """,
            """
            nonmutating set {
                log_\(raw: name).wrappedValue("\(raw: name)", String(describing: newValue))
                \(raw: name)_storage.wrappedValue = newValue
            }
            """,
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let (name, type, _) = stateProperty(declaration) else { return [] }
        let typeText = type.trimmedDescription
        return [
            "private let \(raw: name)_storage: State<\(raw: typeText)>",
            "private let log_\(raw: name) = Environment(\\.testLog)",
            """
            private var `$\(raw: name)`: Binding<\(raw: typeText)> {
                Binding(
                    get: { self.\(raw: name) },
                    set: { self.\(raw: name) = $0 }
                )
            }
            """,
        ]
    }

    /// The `var`'s (name, type, default) — nil for any shape the macro skips.
    private static func stateProperty(
        _ declaration: some DeclSyntaxProtocol
    ) -> (name: String, type: TypeSyntax, defaultValue: ExprSyntax)? {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
            !isStatic(varDecl),
            varDecl.bindingSpecifier.tokenKind == .keyword(.var),
            varDecl.bindings.count == 1, let binding = varDecl.bindings.first,
            let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
            binding.accessorBlock == nil,
            let defaultValue = binding.initializer?.value,
            let type = binding.typeAnnotation?.type ?? inferredLiteralType(defaultValue)
        else { return nil }
        return (pattern.identifier.text, type, defaultValue)
    }
}

/// `@TestAction private var save: (Item) -> Void = { _ in }` — the property's
/// own getter returns the stored closure wrapped with logging; reading `save`
/// IS the logged action, nothing extra to wire:
/// - accessors: an init accessor funneling the inline default into the
///   storage, and a getter returning `{ a0 in log…; storage(a0) }` — the
///   wrapper logs `("save", payload)` then forwards — payload `""` for zero
///   arguments, `String(describing:)` of the bare argument for one, of a
///   tuple beyond; `async`/`throws`/return value carried through
///   (`await` on the log only for `@Sendable async` types, see
///   `wrapperClosure`).
/// - `private let save_storage: (Item) -> Void` + `private let log_save =
///   Environment(\.testLog)`.
///
/// Closures only, and `var` — the compiler refuses accessor expansion on
/// `let`. No setter: an action is wired, not mutated.
public enum TestActionMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let (name, type, function) = actionProperty(declaration) else { return [] }
        return [
            """
            @storageRestrictions(initializes: \(raw: name)_storage)
            init(initialValue) {
                \(raw: name)_storage = initialValue
            }
            """,
            """
            get {
                let log = log_\(raw: name).wrappedValue
                let storage = \(raw: name)_storage
                return \(raw: wrapperClosure(
                    name: name, function: function, isSendable: isSendableType(type)))
            }
            """,
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let (name, type, _) = actionProperty(declaration) else { return [] }
        return [
            "private let \(raw: name)_storage: \(raw: type.trimmedDescription)",
            "private let log_\(raw: name) = Environment(\\.testLog)",
        ]
    }

    /// The `var` closure's (name, type, function type) — nil for any shape the
    /// macro skips.
    private static func actionProperty(
        _ declaration: some DeclSyntaxProtocol
    ) -> (name: String, type: TypeSyntax, function: FunctionTypeSyntax)? {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
            !isStatic(varDecl),
            varDecl.bindingSpecifier.tokenKind == .keyword(.var),
            varDecl.bindings.count == 1, let binding = varDecl.bindings.first,
            let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
            binding.accessorBlock == nil,
            binding.initializer != nil,
            let type = binding.typeAnnotation?.type,
            let function = functionType(of: type)
        else { return nil }
        return (pattern.identifier.text, type, function)
    }
}

// MARK: - Helpers

private func isStatic(_ varDecl: VariableDeclSyntax) -> Bool {
    varDecl.modifiers.contains {
        $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
    }
}

/// True if the annotation spells `@Sendable` anywhere on the function type.
private func isSendableType(_ type: TypeSyntax) -> Bool {
    guard let attributed = type.as(AttributedTypeSyntax.self) else {
        if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
            let inner = tuple.elements.first?.type
        {
            return isSendableType(inner)
        }
        return false
    }
    let spelled = attributed.attributes.contains { item in
        guard case .attribute(let attr) = item else { return false }
        return attr.attributeName.trimmedDescription == "Sendable"
    }
    return spelled || isSendableType(attributed.baseType)
}

/// The function type inside a possibly attributed/parenthesized annotation
/// (`@Sendable () -> Void`, `((Int) -> Void)`), or nil for a non-function type.
private func functionType(of type: TypeSyntax) -> FunctionTypeSyntax? {
    if let fn = type.as(FunctionTypeSyntax.self) { return fn }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return functionType(of: attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
        let inner = tuple.elements.first?.type
    {
        return functionType(of: inner)
    }
    return nil
}

/// `{ a0, a1 in log("move", (a0, a1)); [return ][try ][await ]storage(a0, a1) }`
/// — payload is `()` for zero arguments, the bare argument for one, a tuple
/// beyond. `log` and `storage` are locals the getter extracts first, so the
/// wrapper captures two plain values, never `self` (the log value is
/// `@Sendable`, and not dragging the whole view copy into the closure keeps it
/// clean for `async`/`@Sendable` action types). Environment resolution happens
/// at the view copy's install either way — see CLAUDE.md.
private func wrapperClosure(name: String, function: FunctionTypeSyntax, isSendable: Bool)
    -> String
{
    let parameters = (0..<function.parameters.count).map { "a\($0)" }
    let list = parameters.joined(separator: ", ")
    // Zero arguments → empty-string value, not a described `()`.
    let payload =
        switch parameters.count {
        case 0: "\"\""
        case 1: "String(describing: a0)"
        default: "String(describing: (\(list)))"
        }
    var call = "storage(\(list))"
    if function.effectSpecifiers?.asyncSpecifier != nil { call = "await " + call }
    if function.effectSpecifiers?.throwsClause != nil { call = "try " + call }
    let returnType = function.returnClause.type.trimmedDescription
    if returnType != "Void" && returnType != "()" { call = "return " + call }
    let signature = parameters.isEmpty ? "" : " \(list) in"
    // The seam is @MainActor. Only a @Sendable async wrapper needs `await` —
    // it's the one shape that can't inherit the host's main-actor isolation,
    // so the log call genuinely hops (awaited IN ORDER before forwarding —
    // deliberately no fire-and-forget Task, which could reorder log lines
    // against synchronous state writes). A non-Sendable closure inherits the
    // isolation and calls the log synchronously; `await` there draws the
    // compiler's unnecessary-await warning (verified directly).
    let logCall =
        (isSendable && function.effectSpecifiers?.asyncSpecifier != nil ? "await " : "")
        + "log(\"\(name)\", \(payload))"
    return """
        {\(signature)
                \(logCall)
                \(call)
            }
        """
}
