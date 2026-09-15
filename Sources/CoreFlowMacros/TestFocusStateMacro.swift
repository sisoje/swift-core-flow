import SwiftSyntax
import SwiftSyntaxMacros

/// `@TestFocusState private var focus: Field?` — a drop-in `@FocusState`
/// that logs, the fourth macro in the `@TestState` family. The property
/// becomes COMPUTED over a self-initialized `FocusState<T>` peer —
/// `@FocusState` has no `init(wrappedValue:)`, so there is never an inline
/// default to funnel, and the property is never a memberwise-init parameter
/// whatever its access level. The one logging point is the setter. `$name`
/// forwards the REAL `FocusState<T>.Binding` — `.focused(_:equals:)` demands
/// that exact nominal type, and it has no public initializer to wrap
/// (verified directly) — so writes through the binding (the SYSTEM moving
/// focus) deliberately don't log: scheduler-owned timing has no place in a
/// snapshot log, same criterion as getters-don't-log. The property logs,
/// the projection wires.
///
/// Required shape: a stored instance `var` with a type annotation and no
/// initial value — anything else THROWS, a compile error at the attribute
/// (the family-wide policy, and this macro is why: a skipped
/// `@TestFocusState var focus = false` would compile as a plain, unmanaged
/// stored property that never logs, and the compiler accepts macro-added
/// accessors on an initialized `var` without complaint — verified
/// directly — so only the macro itself can refuse it).
public enum TestFocusStateMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        try focusAccessors(declaration, attribute: "TestFocusState")
    }

    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        focusPeers(declaration, attribute: "TestFocusState", wrapper: "FocusState")
    }
}

/// `@TestAccessibilityFocusState` — the same expansion over
/// `AccessibilityFocusState`, an exact `FocusState` clone interface-wise
/// (verified against the SwiftUI swiftinterface: the same `init()`
/// overloads for `Bool` and optionals, a `Binding` with a settable
/// `wrappedValue` and no public initializer, and
/// `.accessibilityFocused(_:equals:)` demanding that nominal binding).
public enum TestAccessibilityFocusStateMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        try focusAccessors(declaration, attribute: "TestAccessibilityFocusState")
    }

    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        focusPeers(
            declaration, attribute: "TestAccessibilityFocusState", wrapper: "AccessibilityFocusState"
        )
    }
}

private func focusAccessors(
    _ declaration: some DeclSyntaxProtocol, attribute: String
) throws -> [AccessorDeclSyntax] {
    let (name, _) = try validatedFocus(declaration, attribute: attribute)
    return [
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

private func focusPeers(
    _ declaration: some DeclSyntaxProtocol, attribute: String, wrapper: String
) -> [DeclSyntax] {
    // The accessor role reports the error; throwing here too would
    // duplicate it.
    guard let (name, type) = try? validatedFocus(declaration, attribute: attribute) else { return [] }
    let typeText = type.trimmedDescription
    return [
        "private let \(raw: name)_storage: \(raw: wrapper)<\(raw: typeText)> = \(raw: wrapper)()",
        "private let log_\(raw: name) = TestLog()",
        """
        private var `$\(raw: name)`: \(raw: wrapper)<\(raw: typeText)>.Binding {
            \(raw: name)_storage.projectedValue
        }
        """,
    ]
}

/// The `var`'s (name, type) — any other shape throws, a compile error
/// at the attribute stating the required shape.
/// `FocusState()` only exists for `Bool` and optional values — a
/// well-shaped property with any other annotation still fails in the
/// compiler's own words on the generated peer, exactly like the live
/// wrapper.
private func validatedFocus(
    _ declaration: some DeclSyntaxProtocol, attribute: String
) throws -> (name: String, type: TypeSyntax) {
    guard let varDecl = declaration.as(VariableDeclSyntax.self),
          !isStatic(varDecl),
          varDecl.bindingSpecifier.tokenKind == .keyword(.var),
          varDecl.bindings.count == 1, let binding = varDecl.bindings.first,
          let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
          binding.accessorBlock == nil,
          binding.initializer == nil,
          let type = binding.typeAnnotation?.type
    else {
        throw MacroExpansionErrorMessage(
            "@\(attribute) requires a stored instance 'var' with a type annotation (`Bool` or an optional) and no initial value."
        )
    }
    return (pattern.identifier.text, type)
}
