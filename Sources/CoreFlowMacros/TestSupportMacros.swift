import SwiftSyntax
import SwiftSyntaxMacros

// Per-property mutation-logging macros for test hosts. Both generate
// `private let log_x = TestLog()` (TestSupport.swift explains why not
// `@Environment` sugar). Required shape: a stored `var` with an initial
// value; anything else THROWS from expansion — a compile error at the
// attribute, never a silent skip (the family policy; rationale in
// CLAUDE.md's @TestFocusState section).

/// `@TestState private var count: Int = 0` — a drop-in `@State` that logs.
/// The property reads/writes a generated `State` storage, so it stays LIVE
/// exactly like `@State`'s own wrappedValue; the one logging point is the
/// setter, and the generated `$count` binding routes through the property
/// itself, so binding writes log through that same setter. Works on a `var`
/// of ANY type, closures included — a `var` closure means someone wants to
/// mutate the closure itself, and the binding is exactly that. Type from
/// the annotation or the shared three-literal inference.
public enum TestStateMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        let (name, _) = try validated(declaration)
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
        of _: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // The accessor role reports the error; throwing here too would
        // duplicate it.
        guard let (name, type) = try? validated(declaration) else { return [] }
        let typeText = type.trimmedDescription
        return [
            "private let \(raw: name)_storage: State<\(raw: typeText)>",
            "private let log_\(raw: name) = TestLog()",
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

    /// The `var`'s (name, type) — any other shape throws, a compile error
    /// at the attribute stating the required shape.
    private static func validated(
        _ declaration: some DeclSyntaxProtocol
    ) throws -> (name: String, type: TypeSyntax) {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              !isStatic(varDecl),
              varDecl.bindingSpecifier.tokenKind == .keyword(.var),
              varDecl.bindings.count == 1, let binding = varDecl.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
              binding.accessorBlock == nil,
              let defaultValue = binding.initializer?.value,
              let type = binding.typeAnnotation?.type ?? inferredLiteralType(defaultValue)
        else {
            throw MacroExpansionErrorMessage(
                "@TestState requires a stored instance 'var' with an inline default and an explicit type (or a bare Bool/Int/String literal default)."
            )
        }
        return (pattern.identifier.text, type)
    }
}

/// `@TestAction private var save: (Item) -> Void = { _ in }` — the getter
/// returns the stored closure wrapped with logging; reading `save` IS the
/// logged action, nothing extra to wire (payload shapes and effect handling:
/// `wrapperClosure` below). Closures only, and `var` — the compiler refuses
/// accessor expansion on `let`. No setter: an action is wired, not mutated.
public enum TestActionMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        let (name, type, function) = try validated(declaration)
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
                    name: name, function: function, isSendable: isSendableType(type)
                ))
            }
            """,
        ]
    }

    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // The accessor role reports the error; throwing here too would
        // duplicate it.
        guard let (name, type, _) = try? validated(declaration) else { return [] }
        return [
            "private let \(raw: name)_storage: \(raw: type.trimmedDescription)",
            "private let log_\(raw: name) = TestLog()",
        ]
    }

    /// The `var` closure's (name, type, function type) — any other shape
    /// throws, a compile error at the attribute stating the required shape.
    private static func validated(
        _ declaration: some DeclSyntaxProtocol
    ) throws -> (name: String, type: TypeSyntax, function: FunctionTypeSyntax) {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              !isStatic(varDecl),
              varDecl.bindingSpecifier.tokenKind == .keyword(.var),
              varDecl.bindings.count == 1, let binding = varDecl.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
              binding.accessorBlock == nil,
              binding.initializer != nil,
              let type = binding.typeAnnotation?.type,
              let function = functionType(of: type)
        else {
            throw MacroExpansionErrorMessage(
                "@TestAction requires a stored instance 'var' closure with an inert inline default (e.g. `= { _ in }`)."
            )
        }
        return (pattern.identifier.text, type, function)
    }
}

// MARK: - Helpers

/// Shared across the family (`UnstructuredTaskMacro`, `TestFocusStateMacro`).
func isStatic(_ varDecl: VariableDeclSyntax) -> Bool {
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
        guard case let .attribute(attr) = item else { return false }
        return attr.attributeName.trimmedDescription == "Sendable"
    }
    return spelled || isSendableType(attributed.baseType)
}

/// The function type inside a possibly attributed/parenthesized annotation
/// (`@Sendable () -> Void`, `((Int) -> Void)`), or nil for a non-function type.
private func functionType(of type: TypeSyntax) -> FunctionTypeSyntax? {
    if let fn = type.as(FunctionTypeSyntax.self) {
        return fn
    }
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
/// — payload is `""` for zero arguments, the described bare argument for
/// one, a described tuple beyond. `log` and `storage` are locals the getter extracts first, so the
/// wrapper captures two plain values, never `self` (the log value is
/// `@Sendable`, and not dragging the whole view copy into the closure keeps it
/// clean for `async`/`@Sendable` action types). Environment resolution happens
/// at the view copy's install either way — see CLAUDE.md.
private func wrapperClosure(name: String, function: FunctionTypeSyntax, isSendable: Bool)
    -> String
{
    let parameters = (0 ..< function.parameters.count).map { "a\($0)" }
    let list = parameters.joined(separator: ", ")
    // Zero arguments → empty-string value, not a described `()`.
    let payload =
        switch parameters.count {
        case 0: "\"\""
        case 1: "String(describing: a0)"
        default: "String(describing: (\(list)))"
        }
    var call = "storage(\(list))"
    if function.effectSpecifiers?.asyncSpecifier != nil {
        call = "await " + call
    }
    if function.effectSpecifiers?.throwsClause != nil {
        call = "try " + call
    }
    let returnType = function.returnClause.type.trimmedDescription
    if returnType != "Void" && returnType != "()" {
        call = "return " + call
    }
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
