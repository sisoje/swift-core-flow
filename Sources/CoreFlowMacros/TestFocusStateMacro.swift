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
/// initial value — anything else THROWS, a compile error at the attribute.
/// Deliberately not the family's silent-skip policy: a skipped
/// `@TestFocusState var focus = false` would compile as a plain, unmanaged
/// stored property that never logs — and the compiler accepts macro-added
/// accessors on an initialized `var` without complaint (verified directly),
/// so only the macro itself can refuse it.
public enum TestFocusStateMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        let (name, _) = try validated(declaration)
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

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // The accessor role reports the error; throwing here too would
        // duplicate it.
        guard let (name, type) = try? validated(declaration) else { return [] }
        let typeText = type.trimmedDescription
        return [
            "private let \(raw: name)_storage: FocusState<\(raw: typeText)> = FocusState()",
            "private let log_\(raw: name) = TestLog()",
            """
            private var `$\(raw: name)`: FocusState<\(raw: typeText)>.Binding {
                \(raw: name)_storage.projectedValue
            }
            """,
        ]
    }

    /// The property's (name, type), or a thrown error naming what's wrong.
    /// `FocusState()` only exists for `Bool` and optional values — a
    /// well-shaped property with any other annotation still fails in the
    /// compiler's own words on the generated peer, exactly like the live
    /// wrapper.
    private static func validated(
        _ declaration: some DeclSyntaxProtocol
    ) throws -> (name: String, type: TypeSyntax) {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
            !isStatic(varDecl),
            varDecl.bindings.count == 1, let binding = varDecl.bindings.first,
            let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
            binding.accessorBlock == nil
        else {
            throw MacroExpansionErrorMessage(
                "@TestFocusState must attach to a single stored instance property.")
        }
        guard varDecl.bindingSpecifier.tokenKind == .keyword(.var) else {
            throw MacroExpansionErrorMessage(
                "@TestFocusState must attach to a 'var' — like @FocusState, focus is view-managed state, not a constant."
            )
        }
        guard binding.initializer == nil else {
            throw MacroExpansionErrorMessage(
                "@TestFocusState can't take an initial value — like @FocusState, focus always starts at the reset value (false/nil)."
            )
        }
        guard let type = binding.typeAnnotation?.type else {
            throw MacroExpansionErrorMessage(
                "@TestFocusState needs an explicit type annotation (Bool or an optional) to spell its FocusState storage."
            )
        }
        return (pattern.identifier.text, type)
    }
}
