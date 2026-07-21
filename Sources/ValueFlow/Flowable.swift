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
/// and is **excluded** from the init (though not from `OutFlow`/`Core`
/// — see below), so `@Flowable` works cleanly on a `View`. A private property
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
/// ## `FlowableRepresentable` — removed
/// An earlier revision had a separate, opt-in protocol naming this whole shape
/// (`associatedtype InFlowSplat`, `associatedtype InFlow`, `static func
/// makeFlow(_ flow: InFlowSplat) -> Self`, `var inFlow: InFlow { get }`) for
/// generic code written against "any `@Flowable` type" by constraint. Removed —
/// not enough real generic-code use cases materialized to justify keeping a
/// protocol whose only value was naming a shape `@Flowable` already generates
/// concretely on every type it's attached to.
///
/// ## `allFieldNames` — removed
/// An earlier revision had a `static var allFieldNames: [String]` here, listing
/// **every** stored property's name unconditionally, with no filtering at all —
/// including plain private fields with no recognized wrapper (legal at the
/// time), which never appeared in `InFlowSplat`/`InFlow`/`OutFlow` (none of
/// those are tuples over the *whole* type, only over specific field subsets).
/// Removed once it became clear `Reflector.fieldNames(of:)` already covers the
/// same need for any *specific* tuple (`InFlow`, `OutFlow`, …) without a
/// dedicated generated member — the gap that removal opened (a totally-private,
/// non-wrapper field has no tuple type anywhere to reflect over) is moot now
/// anyway: that kind of field is a compile error, not a silently-excluded one
/// (see the property-wrappers section above).
///
/// ## `OutFlow` and the `outFlow` property
/// A wider version of `InFlow`/`inFlow`: every non-private participating property,
/// **plus every recognized private source-of-truth wrapper** —
/// `@Query`/`@State`/`@AppStorage`/`@SceneStorage`/`@FocusState`/
/// `@Environment`/`@Namespace`, no exceptions — a view's own
/// externally-relevant *capturable* state, alongside its public data, in
/// declaration order (not data-layout fields first, wrapper fields appended
/// after). Every property here is already guaranteed one of these two shapes —
/// a private property with no recognized wrapper (`private var cache = 0`) or
/// an unrecognized wrapper (`@StateObject`, …) is refused outright at the
/// property-collection stage, not silently excluded here.
///
/// ```swift
/// @Flowable
/// struct Card: View {
///     @Query private var items: [Item]
///     @State private var isExpanded: Bool = false
///     let title: String
///     // generates:
///     // typealias OutFlow = (items: (wrappedValue: [Item], fetchError: Error?),
///     //                       isExpanded: Binding<Bool>, title: String)
///     // var outFlow: OutFlow {
///     //     (items: #pick(from: _items, \.wrappedValue, \.fetchError),
///     //      isExpanded: $isExpanded, title: title)
///     // }
/// }
/// ```
///
/// - **`@Query` → always `(wrappedValue: WrappedType, fetchError: Error?)`,
///   synthesized via `#pick`** (this package's own `TuplePicker` macro,
///   reused here) — not a passthrough of the declared type, and no
///   `modelContext` either: that's plumbing for issuing further queries/
///   saves, not a snapshot value worth asserting on, so it's left off rather
///   than picked for completeness's sake. `wrappedValue`/`fetchError` are real
///   members of SwiftData's `Query` wrapper *instance*, picked verbatim (no
///   renaming) via `#pick(from: _x, \.wrappedValue, \.fetchError)`, not
///   synthesized placeholders.
/// - **`@State`/`@AppStorage`/`@SceneStorage` → `Binding<WrappedType>`, read via
///   the *projected* value** (`$x`, not `_x` — verified directly that `_x`
///   gives the wrapper instance itself, `State<T>`, not `Binding<T>`) — the
///   view's own externally read-*and-write*-able storage.
/// - **`@FocusState` → `FocusState<WrappedType>.Binding`, read the same way**
///   (`$x`) — **not** `Binding<WrappedType>`, despite the identical read
///   expression. Verified directly against the real SwiftUI interface:
///   `FocusState<T>.Binding` (its own `projectedValue` type) exposes only
///   `wrappedValue`, no public initializer at all and no conversion to
///   `Binding<T>` — so it can't share the row above, even though both are
///   reached via `$x`.
/// - **`@Environment`/`@Namespace` → the plain declared type**, read the same
///   way any non-private field is (`x`) — no exclusion. A captured value
///   going stale if the real environment changes, or `@Environment`'s own
///   mocking story, are things worth knowing about the *snapshot*, not
///   reasons to leave the field out of it.
/// - **Every recognized wrapper kind needs an explicit type even though it's
///   private** — every other private property is exempt from the "needs a type"
///   rule, but `OutFlow` reads the type to build its field, so the exemption
///   doesn't extend to any of them. `@Namespace` is the one exception — its
///   wrapped type is always `Namespace.ID`, so there's nothing to annotate.
@attached(
    member, names: named(init), named(InFlowSplat), named(makeFlow), named(InFlow),
    named(inFlow), named(OutFlow), named(outFlow)
)
public macro Flowable() =
    #externalMacro(
        module: "ValueFlowMacros",
        type: "FlowableMacro"
    )
