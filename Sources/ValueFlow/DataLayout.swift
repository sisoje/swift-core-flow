/// Generates a memberwise `init` for the struct it is attached to, at the struct's
/// own access level — plus two typealiases and two members bridging to/from them:
/// an unlabeled `InFlowSplat` and a `makeFlow(_:)` factory for building
/// `Self` *from* one, and a labeled `InFlow` with an `inFlow` computed property for
/// reading the current instance's data back *out*.
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
///     // public typealias InFlowSplat = (UUID, Bool)
///     // public static func makeFlow(_ flow: InFlowSplat) -> Self {
///     //     Self(id: flow.0, isActive: flow.1)
///     // }
///     // public typealias InFlow = (id: UUID, isActive: Bool)
///     // public var inFlow: InFlow {
///     //     (id: self.id, isActive: self.isActive)
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
/// ## The `InFlowSplat` typealias (in) and `makeFlow(_:)`
/// Alongside the init, `@DataLayout` declares `InFlowSplat` — the same
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
///   ever reshapes the *init parameter*), so every field just reads `self.x`
///   directly — except `@Binding`, which reads its projected form `self._x` to
///   match `InFlowSplat`'s `Binding<T>` field type.
/// - **Round-trips through `makeFlow(_:)` with no manual conversion**:
///   `Self.makeFlow(someInstance.inFlow)` works as-is, verified
///   directly — an `InFlow` value converts into `InFlowSplat`'s unlabeled
///   parameter the same way any differently-labeled tuple does.
///
/// ## `DataLayoutRepresentable` — removed
/// An earlier revision had a separate, opt-in protocol naming this whole shape
/// (`associatedtype InFlowSplat`, `associatedtype InFlow`, `static func
/// makeFlow(_ flow: InFlowSplat) -> Self`, `var inFlow: InFlow { get }`) for
/// generic code written against "any `@DataLayout` type" by constraint. Removed —
/// not enough real generic-code use cases materialized to justify keeping a
/// protocol whose only value was naming a shape `@DataLayout` already generates
/// concretely on every type it's attached to.
///
/// ## `allFieldNames` — removed
/// An earlier revision had a `static var allFieldNames: [String]` here, listing
/// **every** stored property's name unconditionally, with no filtering at all —
/// including plain private fields with no recognized wrapper, which never appear
/// in `InFlowSplat`/`InFlow`/`OutFlow` (none of those are tuples over the
/// *whole* type, only over specific field subsets). Removed once it became clear
/// `Reflector.fieldNames(of:)` already covers the same need for any *specific*
/// tuple (`InFlow`, `OutFlow`, …) without a dedicated generated member — the
/// one real gap that removal opens is a totally-private, non-wrapper field
/// (`private var cache = 0`), which still has no tuple type anywhere to reflect
/// over. Accepted as YAGNI for now; revisit if that specific need actually comes
/// up.
///
/// ## `OutFlow` and the `outFlow` property
/// A wider version of `InFlow`/`inFlow`: every non-private participating property,
/// **plus** private `@Query`/`@State`/`@AppStorage`/`@FocusState` properties — a
/// view's own externally-relevant *capturable* state, alongside its public data —
/// in declaration order (not data-layout fields first, wrapper fields appended
/// after). Everything else private (a plain `private var cache = 0`,
/// `@StateObject`, …) stays excluded.
///
/// ```swift
/// @DataLayout
/// struct Card: View {
///     @Query private var items: [Item]
///     @State private var isExpanded: Bool = false
///     let title: String
///     // generates:
///     // typealias OutFlow = (items: (result: [Item], fetchError: Error?, modelContext: ModelContext),
///     //                       isExpanded: Binding<Bool>, title: String)
///     // var outFlow: OutFlow {
///     //     (items: (result: self.items, fetchError: self._items.fetchError, modelContext: self._items.modelContext),
///     //      isExpanded: self.$isExpanded, title: self.title)
///     // }
/// }
/// ```
///
/// - **`@Query` → always `(result: WrappedType, fetchError: Error?, modelContext:
///   ModelContext)`, synthesized** — not a passthrough of the declared type.
///   `fetchError`/`modelContext` are real members of SwiftData's `Query` wrapper
///   *instance* (`self._x.fetchError`, `self._x.modelContext`), not synthesized
///   placeholders.
/// - **`@State`/`@AppStorage` → `Binding<WrappedType>`, read via the *projected*
///   value** (`self.$x`, not `self._x` — verified directly that `_x` gives the
///   wrapper instance itself, `State<T>`, not `Binding<T>`) — the view's own
///   externally read-*and-write*-able storage.
/// - **`@FocusState` → `FocusState<WrappedType>.Binding`, read the same way**
///   (`self.$x`) — **not** `Binding<WrappedType>`, despite the identical read
///   expression. Verified directly against the real SwiftUI interface:
///   `FocusState<T>.Binding` (its own `projectedValue` type) exposes only
///   `wrappedValue`, no public initializer at all and no conversion to
///   `Binding<T>` — so it can't share the row above, even though both are
///   reached via `self.$x`.
/// - **`@Environment` is deliberately excluded**, unlike the other three — not
///   because it's technically uncapturable (a plain, unattributed value works
///   fine; `@StatelessNode`, a separate macro, captures it exactly that way), but
///   because a captured snapshot goes stale the moment the real environment
///   changes, and `@Environment`'s own mocking story (inject a different value
///   where the type is constructed/hosted) already covers testing it without
///   this package's help. `@StatelessNode` makes the opposite call and captures it
///   anyway, for the same reason it treats every field uniformly.
/// - **These four wrapper kinds need an explicit type even though they're
///   private** — every other private property is exempt from the "needs a type"
///   rule, but `OutFlow` reads their type to build its field, so the exemption
///   doesn't extend to them. (`@Environment` also needs an explicit type, for
///   `@StatelessNode`'s sake, even though `OutFlow` itself no longer reads it.)
@attached(
    member, names: named(init), named(InFlowSplat), named(makeFlow), named(InFlow),
    named(inFlow), named(OutFlow), named(outFlow)
)
public macro DataLayout() =
    #externalMacro(
        module: "ValueFlowMacros",
        type: "DataLayoutMacro"
    )
