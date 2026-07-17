/// Generates a memberwise `init` for the struct it is attached to, at the struct's
/// own access level — plus a `DataLayout` typealias bundling the same properties
/// into a tuple.
///
/// Swift only ever synthesizes an **internal** memberwise initializer, and only
/// when you write no init of your own. `@MemberwiseInit` writes an explicit one that
/// matches the struct's access — the `public` memberwise init Swift refuses to give
/// a public type:
///
/// ```swift
/// @MemberwiseInit
/// public struct User {
///     public let id: UUID
///     public var isActive: Bool = false
///     // generates:
///     // public init(id: UUID, isActive: Bool = false) {
///     //     self.id = id
///     //     self.isActive = isActive
///     // }
///     // public typealias DataLayout = (id: UUID, isActive: Bool)
/// }
/// ```
///
/// ## What it mirrors
/// - Inline `var` defaults become defaulted parameters.
/// - An inline-initialized `let` is a constant, excluded from `init`.
/// - Function-typed properties get `@escaping` (incl. `@MainActor`/`@Sendable` ones).
/// - Computed properties and `static`/`class` members are skipped.
///
/// ## Property wrappers (tuned for SwiftUI)
/// Only `@Binding` is threaded into the init, as a projected `Binding<T>` parameter.
/// Every other wrapper — `@State`, `@Environment`, `@StateObject`, … — is view-owned
/// or injected and is **excluded** from the init, so `@MemberwiseInit` works cleanly
/// on a `View`.
///
/// A property that becomes an init parameter must carry an explicit type annotation
/// (the macro is syntax-only and can't infer a type from a literal).
///
/// ## The `DataLayout` typealias
/// Alongside the init, `@MemberwiseInit` also declares `DataLayout` — the same
/// properties bundled into a tuple type, for uniformity/discoverability rather than
/// as a second constructor. It's built independently of the init's own rendering:
///
/// - **Two or more properties** → a tuple (`(id: UUID, isActive: Bool)`). **Exactly
///   one** collapses to that property's bare type — Swift has no 1-tuples, so
///   `(id: UUID)` as a type is indistinguishable from plain `UUID`. **Zero**
///   properties yields no typealias at all.
/// - **No per-field defaults** and **never `@escaping`** — tuple element types
///   support neither; both are silently dropped, even though the init right above
///   still has them.
/// - **`@ViewBuilder` is ignored** — a stored-value field
///   (`@ViewBuilder let footer: Content`) keeps its own type (`Content`) in the
///   tuple rather than the `() -> Content` builder the init uses; a tuple type has
///   no parameter position for the trailing-closure sugar that wrapping exists to
///   enable, and a closure would make `DataLayout` hold something that isn't
///   `Equatable`.
@attached(member, names: named(init), named(DataLayout))
public macro MemberwiseInit() =
    #externalMacro(
        module: "DataMacrosMacros",
        type: "MemberwiseInitMacro"
    )
