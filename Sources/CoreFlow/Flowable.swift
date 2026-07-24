/// Generates a memberwise `init` for the struct it is attached to, at the struct's
/// own access level — plus two typealiases and two members bridging to/from them:
/// an unlabeled `InFlowSplat` and a `makeFlow(_:)` factory for building
/// `Self` *from* one, and a labeled `InFlow` with an `inFlow` computed property for
/// reading the current instance's data back *out*.
///
/// Swift only ever synthesizes an **internal** memberwise initializer, and only
/// when you write no init of your own. `@Flowable` writes an explicit one that
/// matches the struct's access — the `public` memberwise init Swift refuses to give
/// a public type:
///
/// ```swift
/// @Flowable
/// public struct User {
///     public let id: UUID
///     public var isActive: Bool = false
///     // generates:
///     // public init(id: UUID, isActive: Bool = false) {
///     //     self.id = id
///     //     self.isActive = isActive
///     // }
///     // public typealias InFlowSplat = (UUID, Bool)
///     // public static func makeFlow(_ flow: InFlowSplat) -> Self {
///     //     Self(id: flow.0, isActive: flow.1)
///     // }
///     // public typealias InFlow = (id: UUID, isActive: Bool)
///     // public var inFlow: InFlow {
///     //     (id: id, isActive: isActive)
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
/// `@Binding`/`@Bindable`/`@ViewBuilder` are threaded into the init as real
/// parameters a caller supplies — declaring any of them `private` is a compile
/// error, since that makes them unreachable. Every recognized source-of-truth
/// wrapper — `@State`, `@Environment`, `@Query`, `@AppStorage`, `@SceneStorage`,
/// `@FocusState`, `@Namespace` — is view-owned or injected, must be `private`,
/// and is **excluded** from the init (though not from `@Shell`'s `Core`),
/// so `@Flowable` works cleanly on a `View`. A private property
/// with no property wrapper at all (`private var cache = 0`) is also a compile
/// error — pure data flow has no room for opaque private state that's neither
/// a source of truth nor caller-supplied.
///
/// A property that becomes an init parameter must carry an explicit type
/// annotation — the macro is syntax-only and can't really infer a type from a
/// literal, *except* three unambiguous kinds: `var isOn = false`, `var count = 0`,
/// `var label = "x"` are inferred straight off the literal's own syntax.
///
/// ## The `InFlowSplat` typealias (in) and `makeFlow(_:)`
/// Alongside the init, `@Flowable` declares `InFlowSplat` — the same
/// properties bundled into a tuple type — and a `static func
/// makeFlow(_ flow: InFlowSplat) -> Self` that builds an instance from one.
/// Both are independent of the init's own rendering, and both are declared
/// whenever the type has at least one participating property (collapsing/
/// disappearing together with it):
///
/// - **Two or more properties** → an *unlabeled* tuple (`(UUID, Bool)`, not
///   `(id: UUID, isActive: Bool)`) — deliberately, so any structurally-compatible
///   tuple converts into it, not just one built with these exact field names
///   ("splat" in the name). Verified directly: a tuple *value* already bound
///   with different labels (`let t = (xxx: 1, yyy: 2)`) fails to convert into a
///   *labeled* tuple type of the same shape, but succeeds once the target is
///   unlabeled — Swift only enforces label agreement between two labeled tuple
///   types. A labeled tuple *literal* (`(id: someID, isActive: true)`) converts
///   into the unlabeled target either way, so callers can still write field names
///   for their own readability when constructing the value. The tradeoff: with no
///   labels, the type checker no longer catches two same-typed fields passed in
///   the wrong order.
/// - **Exactly one property** collapses `InFlowSplat` to that property's bare
///   type — Swift has no 1-tuples, so `(id: UUID)` (or even unlabeled `(UUID)`) as
///   a type is indistinguishable from plain `UUID`. `makeFlow(_:)` then
///   just uses the value directly, no positional index needed.
/// - **No per-field defaults** and **never `@escaping`** — tuple element types
///   support neither; both are silently dropped, even though the init keeps them.
/// - **`@ViewBuilder` is ignored in the typealias** — a stored-value field
///   (`@ViewBuilder let footer: Content`) keeps its own type (`Content`) in the
///   tuple rather than the `() -> Content` builder the init uses; a tuple type has
///   no parameter position for the trailing-closure sugar that wrapping exists to
///   enable, and a closure would make `InFlowSplat` hold something that isn't
///   `Equatable`. `makeFlow(_:)` re-wraps it in a trivial closure
///   (`footer: { flow.2 }`) just to satisfy the init's builder-shaped
///   parameter.
/// - Fields are read **positionally** in `makeFlow(_:)`
///   (`flow.0`, `flow.1`, … in field order), since
///   `InFlowSplat` itself carries no labels.
///
/// ## The `InFlow` typealias (out) and the `inFlow` property
/// The reverse direction: `InFlow` is the same fields and types as
/// `InFlowSplat`, but *labeled* (`(id: UUID, isActive: Bool)`), and the `inFlow`
/// computed property extracts the current instance's values into one. Also
/// declared together, whenever there's at least one participating property.
///
/// - **Readable field access** (`instance.inFlow.id`, not `.0`) and real
///   reflection support: verified directly that `Mirror(reflecting:)` reports each
///   field's actual name over a *labeled* tuple, but only positional labels
///   (`".0"`, `".1"`) over an unlabeled one — `InFlowSplat` alone can't support
///   a generic field-dumping utility, `InFlow` can.
/// - **No wrapping needed for `@ViewBuilder` fields**, unlike
///   `makeFlow(_:)`'s reverse direction: the stored property already
///   holds exactly its own declared type regardless of `@ViewBuilder` (which only
///   ever reshapes the *init parameter*), so every field just reads `x`
///   directly — except `@Binding`, which reads its projected form `$x` to
///   match `InFlowSplat`'s `Binding<T>` field type.
/// - **Round-trips through `makeFlow(_:)` with no manual conversion**:
///   `Self.makeFlow(someInstance.inFlow)` works as-is, verified
///   directly — an `InFlow` value converts into `InFlowSplat`'s unlabeled
///   parameter the same way any differently-labeled tuple does.
///
/// ## Deliberately nothing more
/// These five members are the whole surface. No protocol names the shape
/// (generic code against "any `@Flowable` type" has no proven use case; a
/// protocol's only value would be naming what's already generated concretely
/// on every type). No field-names member (`Reflector.fieldNames(of:
/// SomeType.InFlow.self)` already reports any generated tuple's field
/// names). And no snapshot member wider than `InFlow`: capturing a view's
/// private wrapper state for tests is `@Shell`'s `Core`'s job — a real
/// nominal struct can conform to protocols (a tuple can't), host live, and
/// be constructed with mocks directly — see `Shell.swift`.
@attached(
    member, names: named(init), named(InFlowSplat), named(makeFlow), named(InFlow),
    named(inFlow)
)
public macro Flowable() =
    #externalMacro(
        module: "CoreFlowMacros",
        type: "FlowableMacro"
    )
