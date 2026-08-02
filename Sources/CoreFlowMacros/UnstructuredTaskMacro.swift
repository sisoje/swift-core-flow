import SwiftSyntax
import SwiftSyntaxMacros

/// `@UnstructuredTask private var download: Task<Data, Error>?` — a view-owned
/// slot for a cancellable unstructured `Task` that logs, `@TestState`'s
/// sibling. The property becomes COMPUTED over a self-initialized
/// `State<TaskStorage>` peer — no init accessor, so it can never be a
/// memberwise-init parameter whatever its access level, and the task always
/// starts `nil` (a written `= nil` fails in the compiler's own words: a
/// variable with accessors can't have an initial value). The
/// class-in-`State` box is what buys the lifecycle: replacing the task
/// cancels the previous one (its `willSet`, equality-guarded so
/// self-reassignment is not a cancel), the view leaving the graph cancels
/// the live one (its `deinit`). The one logging point is the setter —
/// `(name, "task"/"nil")`, deterministic where a described `Task` is not —
/// and the generated `$name` binding routes through the property, so binding
/// writes cancel and log identically. Required shape: a stored `var` with an
/// optional-sugared type annotation (`T?` — the storage's element is that
/// type minus the `?`, `CancellableTask`-constrained, so `Task`'s own
/// generic arguments are never parsed and a typealias works; `T!` and
/// long-form `Optional<T>` are skipped); anything else generates nothing,
/// no diagnostics.
public enum UnstructuredTaskMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let (name, _, _) = taskProperty(declaration) else { return [] }
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
        guard let (name, element, optional) = taskProperty(declaration) else { return [] }
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

    /// The `var`'s (name, optional's wrapped type, optional type) — nil for
    /// any shape the macro skips. Unlike `@TestState`, the annotation is
    /// required and must be optional-sugared (`T?`): the storage field's
    /// element type is spelled from it with the `?` stripped. Deliberately
    /// no initializer check — the accessors make the property computed, so
    /// a written default is the compiler's own error, never a silent skip
    /// that would leave a plain, unmanaged stored property behind.
    private static func taskProperty(
        _ declaration: some DeclSyntaxProtocol
    ) -> (name: String, element: TypeSyntax, optional: TypeSyntax)? {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
            !isStatic(varDecl),
            varDecl.bindingSpecifier.tokenKind == .keyword(.var),
            varDecl.bindings.count == 1, let binding = varDecl.bindings.first,
            let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
            binding.accessorBlock == nil,
            let optional = binding.typeAnnotation?.type.as(OptionalTypeSyntax.self)
        else { return nil }
        return (pattern.identifier.text, optional.wrappedType, TypeSyntax(optional))
    }
}
