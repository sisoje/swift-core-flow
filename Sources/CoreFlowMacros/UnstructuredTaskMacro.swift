import SwiftSyntax
import SwiftSyntaxMacros

/// `@UnstructuredTask private var download: Task<Data, Error>?` — a view-owned
/// slot for a cancellable unstructured `Task` that logs, `@TestState`'s
/// sibling. The property becomes COMPUTED over a self-initialized
/// `State<TaskStorage>` peer — no init accessor, so it can never be a
/// memberwise-init parameter whatever its access level, and the task always
/// starts `nil` (a written default is refused by the macro itself — see
/// `validated` below). The
/// class-in-`State` box is what buys the lifecycle: replacing the task
/// cancels the previous one (its `willSet`, equality-guarded so
/// self-reassignment is not a cancel), the view leaving the graph cancels
/// the live one (its `deinit`). The one logging point is the setter —
/// `(name, "task"/"nil")`, deterministic where a described `Task` is not —
/// and the generated `$name` binding routes through the property, so binding
/// writes cancel and log identically. Required shape: a stored `var` with an
/// optional-sugared type annotation and no initial value (`T?` — the
/// storage's element is that type minus the `?`,
/// `CancellableTask`-constrained, so `Task`'s own generic arguments are
/// never parsed and a typealias works); anything else THROWS from
/// expansion — a compile error at the attribute, never a silent skip
/// (see `validated` below).
public enum UnstructuredTaskMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        let (name, _, _) = try validated(declaration)
        return [
            """
            get {
                \(raw: name)_storage.wrappedValue.task
            }
            """,
            """
            nonmutating set {
                log_\(raw: name).wrappedValue("\(raw: name)", newValue == nil ? "nil" : "task")
                \(raw: name)_storage.wrappedValue.task = newValue
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
        guard let (name, element, optional) = try? validated(declaration) else { return [] }
        let elementText = element.trimmedDescription
        let optionalText = optional.trimmedDescription
        return [
            "private let \(raw: name)_storage: State<TaskStorage<\(raw: elementText)>> = State(wrappedValue: TaskStorage())",
            "private let log_\(raw: name) = TestLog()",
            """
            private var `$\(raw: name)`: Binding<\(raw: optionalText)> {
                Binding(
                    get: { self.\(raw: name) },
                    set: { self.\(raw: name) = $0 }
                )
            }
            """,
        ]
    }

    /// The `var`'s (name, optional's wrapped type, optional type) — any
    /// other shape throws, a compile error at the attribute stating the
    /// required shape. The initializer check is real, not
    /// delegated to the compiler: macro-added accessors on an initialized
    /// `var` draw no compiler error on this toolchain (verified directly —
    /// the written default would compile, never evaluate, and the task
    /// would silently start nil).
    private static func validated(
        _ declaration: some DeclSyntaxProtocol
    ) throws -> (name: String, element: TypeSyntax, optional: TypeSyntax) {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
            !isStatic(varDecl),
            varDecl.bindingSpecifier.tokenKind == .keyword(.var),
            varDecl.bindings.count == 1, let binding = varDecl.bindings.first,
            let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
            binding.accessorBlock == nil,
            binding.initializer == nil,
            let optional = binding.typeAnnotation?.type.as(OptionalTypeSyntax.self)
        else {
            throw MacroExpansionErrorMessage(
                "@UnstructuredTask requires a stored instance 'var' with an optional-sugared task type annotation (`T?`) and no initial value."
            )
        }
        return (pattern.identifier.text, optional.wrappedType, TypeSyntax(optional))
    }
}
