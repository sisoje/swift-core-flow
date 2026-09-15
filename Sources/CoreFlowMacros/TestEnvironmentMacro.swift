import SwiftSyntax
import SwiftSyntaxMacros

/// `@TestEnvironment(\.dismiss) private var dismiss: () -> Void` — a logged
/// call through a REAL environment value, the fifth macro in the `@TestState`
/// family and `@Shell`'s substitution for an `@Environment` action on `Core`.
/// A live instrument, not a mock: the peer is the real `Environment(\.kp)`,
/// so hosted the actual `DismissAction`/`OpenURLAction` runs;
/// unhosted the environment's default runs (a no-op for the sealed actions).
/// The getter returns `@TestAction`'s wrapper closure — log the name and the
/// described arguments, then forward — so `dismiss()` reads the same on the
/// host and on `Core`. Anything callable without labels forwards; a labeled
/// action (`openWindow(id:)`) has no closure spelling and stays verbatim.
public enum TestEnvironmentMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        let (name, type, function) = try validated(node, declaration)
        return [
            """
            get {
                let log = log_\(raw: name).wrappedValue
                let storage = \(raw: name)_storage.wrappedValue
                return \(raw: wrapperClosure(
                    name: name, function: function, isSendable: isSendableType(type)
                ))
            }
            """,
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // The accessor role reports the error; throwing here too would
        // duplicate it.
        guard let (name, _, _) = try? validated(node, declaration),
              let keyPath = keyPathArgument(node)
        else { return [] }
        return [
            "private let \(raw: name)_storage = Environment(\(raw: keyPath))",
            "private let log_\(raw: name) = TestLog()",
        ]
    }

    /// The `var`'s (name, type, function type) — any other shape throws, a
    /// compile error at the attribute stating the required shape.
    private static func validated(
        _ node: AttributeSyntax, _ declaration: some DeclSyntaxProtocol
    ) throws -> (name: String, type: TypeSyntax, function: FunctionTypeSyntax) {
        guard keyPathArgument(node) != nil,
              let varDecl = declaration.as(VariableDeclSyntax.self),
              !isStatic(varDecl),
              varDecl.bindingSpecifier.tokenKind == .keyword(.var),
              varDecl.bindings.count == 1, let binding = varDecl.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
              binding.accessorBlock == nil,
              binding.initializer == nil,
              let type = binding.typeAnnotation?.type,
              let function = functionType(of: type)
        else {
            throw MacroExpansionErrorMessage(
                "@TestEnvironment(\\.keyPath) requires a stored instance 'var' with a function-type annotation and no initial value."
            )
        }
        return (pattern.identifier.text, type, function)
    }
}

/// The key-path argument of an `@Environment(\.kp)`/`@TestEnvironment(\.kp)`
/// attribute, as written; nil when the attribute carries no argument.
func keyPathArgument(_ attribute: AttributeSyntax) -> String? {
    attribute.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.trimmedDescription
}
