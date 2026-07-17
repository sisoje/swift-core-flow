/// Generates a memberwise `init` for the struct it is attached to, at the struct's
/// own access level — plus a `DataLayout` typealias bundling the same properties
/// into an unlabeled tuple, and a `make(dataLayout:)` static factory constructing
/// `Self` from one.
///
/// Swift only ever synthesizes an **internal** memberwise initializer, and only
/// when you write no init of your own. `@DataLayout` writes an explicit one that
/// matches the struct's access — the `public` memberwise init Swift refuses to give
/// a public type:
///
/// ```swift
/// @DataLayout
/// public struct User {
///     public let id: UUID
///     public var isActive: Bool = false
///     // generates:
///     // public init(id: UUID, isActive: Bool = false) {
///     //     self.id = id
///     //     self.isActive = isActive
///     // }
///     // public typealias DataLayout = (UUID, Bool)
///     // public static func make(dataLayout: DataLayout) -> Self {
///     //     Self(id: dataLayout.0, isActive: dataLayout.1)
///     // }
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
/// or injected and is **excluded** from the init, so `@DataLayout` works cleanly
/// on a `View`.
///
/// A property that becomes an init parameter must carry an explicit type annotation
/// (the macro is syntax-only and can't infer a type from a literal).
///
/// ## The `DataLayout` typealias
/// Alongside the init, `@DataLayout` also declares `DataLayout` — the same
/// properties bundled into a tuple type. It's built independently of the init's own
/// rendering:
///
/// - **Two or more properties** → an *unlabeled* tuple (`(UUID, Bool)`, not
///   `(id: UUID, isActive: Bool)`) — deliberately, so any structurally-compatible
///   tuple converts into it, not just one built with these exact field names.
///   Verified directly: a tuple *value* already bound with different labels
///   (`let t = (xxx: 1, yyy: 2)`) fails to convert into a *labeled* tuple type of
///   the same shape, but succeeds once the target is unlabeled — Swift only
///   enforces label agreement between two labeled tuple types. A labeled tuple
///   *literal* (`(id: someID, isActive: true)`) converts into the unlabeled target
///   either way, so callers can still write field names for their own readability
///   when constructing the value. The tradeoff: with no labels, the type checker no
///   longer catches two same-typed fields passed in the wrong order.
/// - **Exactly one property** collapses to that property's bare type — Swift has no
///   1-tuples, so `(id: UUID)` (or even unlabeled `(UUID)`) as a type is
///   indistinguishable from plain `UUID`. **Zero** properties yields no typealias at
///   all.
/// - **No per-field defaults** and **never `@escaping`** — tuple element types
///   support neither; both are silently dropped, even though the init right above
///   still has them.
/// - **`@ViewBuilder` is ignored** — a stored-value field
///   (`@ViewBuilder let footer: Content`) keeps its own type (`Content`) in the
///   tuple rather than the `() -> Content` builder the init uses; a tuple type has
///   no parameter position for the trailing-closure sugar that wrapping exists to
///   enable, and a closure would make `DataLayout` hold something that isn't
///   `Equatable`.
///
/// ## The `make(dataLayout:)` factory
/// A `static func make(dataLayout: DataLayout) -> Self` that builds an instance
/// from a `DataLayout` value — declared whenever `DataLayout` itself is (so it
/// collapses/disappears the same way). It's a static function rather than a second
/// `init` so it works the same on a struct, class, or actor: a delegating second
/// `init` would need `self.init(...)`, which on a class/actor requires the
/// `convenience` keyword and Swift's designated/convenience init rules — a plain
/// static function returning `Self(...)` avoids that entirely. Since `DataLayout`
/// is unlabeled, each field is read positionally (`dataLayout.0`, `dataLayout.1`,
/// … in field order) rather than by name — the one exception being a
/// `@ViewBuilder`-stored value, which is wrapped back into a trivial closure
/// (`{ dataLayout.2 }`), since the primary init wants a builder for it even though
/// `DataLayout` itself stores the plain value.
@attached(member, names: named(init), named(DataLayout), named(make))
public macro DataLayout() =
    #externalMacro(
        module: "DataMacrosMacros",
        type: "DataLayoutMacro"
    )
