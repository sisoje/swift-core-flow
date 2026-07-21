/// Generates a nested `StatelessNode` struct — carrying `@DataLayout` itself — plus a
/// `statelessNode` computed property building one from the current instance. Shares
/// its constructed-field set with `@DataLayout`'s own `OutFlow`/`outFlow`, plus
/// `@Environment` (which `OutFlow` deliberately leaves out — see its own doc
/// comment — but `StatelessNode` still captures): every non-private participating
/// property, plus private `@Environment`/`@Query`/`@State`/`@AppStorage` state,
/// each captured once as a plain value when `.statelessNode` is computed.
///
/// Independent of `@DataLayout` — doesn't replace `OutFlow`/`outFlow`, and works
/// with or without `@DataLayout` also attached (it collects the type's stored
/// properties itself).
///
/// ```swift
/// @StatelessNode
/// struct Card: View {
///     @Query private var items: [Item]
///     @Environment(\.colorScheme) private var colorScheme: ColorScheme
///     @State private var isExpanded: Bool = false
///     let title: String
///     var subtitle: String?
///     // generates:
///     // @DataLayout
///     // struct StatelessNode {
///     //     let items: (result: [Item], fetchError: Error?, modelContext: ModelContext)
///     //     let colorScheme: ColorScheme
///     //     @Binding var isExpanded: Bool
///     //     let title: String
///     //     let subtitle: String?
///     // }
///     // var statelessNode: StatelessNode {
///     //     StatelessNode(items: (result: self.items, fetchError: self._items.fetchError,
///     //                       modelContext: self._items.modelContext),
///     //               colorScheme: self.colorScheme, isExpanded: self.$isExpanded,
///     //               title: self.title, subtitle: self.subtitle)
///     // }
/// }
/// ```
///
/// ## Why `StatelessNode` exists alongside `OutFlow`
/// `OutFlow` is a tuple — structurally convenient, but tuples can't conform to
/// protocols (verified directly: `error: type '(...)' cannot conform to
/// 'Equatable' — only concrete types such as structs, enums and classes can
/// conform to protocols`). `StatelessNode` is a real nominal struct capturing the
/// same data, so it can — `Equatable`/`Codable`/a shared "any stateless snapshot"
/// protocol are all reachable on it in a way they never can be on `OutFlow`.
///
/// ## Why `StatelessNode` needs its own `@DataLayout`, not hand-written members
/// Rather than re-deriving an init/accessors for the nested struct by hand,
/// `@StatelessNode` just declares `StatelessNode`'s stored properties and attaches
/// `@DataLayout` to it. A macro-generated declaration that itself carries another
/// macro's attribute genuinely gets expanded by the compiler — verified directly
/// with a real build: a member macro emitting `@DataLayout public struct Snapshot
/// { ... }` produces a fully working `inFlow`/`makeFlow(_:)`/`InFlowSplat` on
/// `Snapshot`, no different from writing it by hand. `@DataLayout`'s own
/// memberwise-init rendering does the rest, with no new init/accessor logic
/// anywhere in this macro.
///
/// ## Every source-of-truth wrapper becomes a plain, constructed value
/// `@Query`, `@State`/`@AppStorage`, and `@Environment` all become ordinary
/// fields on `StatelessNode`, captured once (as a plain value, read once when
/// `.statelessNode` is computed) rather than kept live — never the original
/// attribute, except `@Binding` (below), which is a deliberate substitution:
/// - `@Query` → the synthesized `(result:, fetchError:, modelContext:)` tuple,
///   no attribute.
/// - `@State`/`@AppStorage` → `@Binding var name: T` — the one case that keeps
///   an attribute, substituted rather than mirrored, since their own storage
///   only installs inside a live SwiftUI view and can't be redeclared as
///   itself on a plain struct.
/// - `@Environment` → a plain `let name: T`, no attribute at all. Not because
///   the value doesn't change — because the *attribute* can't be preserved:
///   `@Environment`'s `wrappedValue` has no public setter (verified directly:
///   `error: cannot assign to property: 'colorScheme' is a get-only
///   property`), and `@DataLayout`'s init always assigns `self.x = x` — a
///   plain, unattributed `let` has no such restriction. Always `let`, not
///   mirroring the original's `let`/`var` (the original is *always* `var`,
///   every property wrapper requires it) — the captured copy is a one-time
///   snapshot, immutable by design. `OutFlow` makes the opposite call and
///   excludes `@Environment` entirely, since a captured snapshot goes stale
///   and its own mocking story doesn't need this package's help — `StatelessNode`
///   captures it anyway, for the same reason it treats every field uniformly.
///
/// **`@State`/`@Environment`/`@Query`/`@AppStorage` must be private** — enforced
/// with a diagnostic (`sourceOfTruthMustBePrivate`, in `StoredProperty.swift`),
/// not accommodated: they're a view's own source of truth, never something a
/// caller supplies (that's what `@Binding` is for), so every renderer can
/// assume all four are always private, with no "what if it's also public" case
/// to reason about.
///
/// ## The rule for everything else: mirror the attribute and type, never the mutability
/// Every field except `@Query` (and `@Environment`, above) is declared on
/// `StatelessNode` with the *original* property's own attribute (if it has one) and
/// declared type — but never its `let`/`var`. `StatelessNode` is a deterministic
/// snapshot, so a field is `var` only where Swift's own property-wrapper rule
/// forces it (a genuine `@propertyWrapper` type requires `var` storage; verified
/// directly, `@Bindable let model: Settings` is a compile error: "property
/// wrapper can only be applied to a 'var'"). Everything else — including `@Query`
/// above — is `let`, regardless of what the original property was declared as:
/// - A plain `var subtitle: String?` becomes `let subtitle: String?` on
///   `StatelessNode` — a captured value, not a re-tweakable one.
/// - A genuine, already-public `@Binding` field mirrors verbatim into exactly
///   the same `@Binding var name: T` form `@State`/`@AppStorage` are
///   *substituted* into above — same payoff, same `@DataLayout` handling, no
///   extra logic needed for this case specifically. `@Binding` is itself a
///   genuine property wrapper, so it keeps `var`.
/// - `@ViewBuilder` mirroring is a real win here, unlike `OutFlow`'s tuple —
///   `OutFlow` has no parameter position for trailing-closure sugar to attach
///   to, so it strips `@ViewBuilder` down to a bare type. `StatelessNode` has a real
///   init (from its own `@DataLayout` expansion), so `@ViewBuilder` mirrored
///   onto its field genuinely buys real builder syntax at `StatelessNode`'s own
///   init call site. `@ViewBuilder` is *not* a `@propertyWrapper` — it's a
///   result-builder attribute, legal directly on `let` (verified directly:
///   `@ViewBuilder let vb: () -> Text` compiles) — so it keeps `let`.
/// - `@Bindable` needs no special handling beyond the general "genuine wrapper
///   keeps var" rule above — `@DataLayout`'s init logic never recognized
///   `@Bindable` specially even on the *original* type (it just does
///   `self.model = model`, legal since `@Bindable`'s wrappedValue is a plain
///   get/set), so mirroring it onto `StatelessNode` reuses that exact unmodified
///   path.
///
/// ## Automatic `View`/`ViewModifier` detection
/// When the attached type's own inheritance clause spells `View` or
/// `ViewModifier` — `struct Card: View` or `struct VM: ViewModifier` — two more
/// things are generated on top of the usual `StatelessNode` struct/`statelessNode`
/// property:
/// - `StatelessNode` is additionally declared `: View` or `: ViewModifier` — a
///   requirement, not an implementation; the real `body`/`body(content:)` is
///   still hand-written, in a separate extension of `StatelessNode`. Swift's own
///   "does not conform to protocol" build error enforces that this gets
///   written at all; a doc comment generated on `StatelessNode` itself (visible via
///   Quick Help/jump-to-definition) says exactly what to write and where —
///   not a diagnostic, since the macro can't know whether the extension
///   already exists elsewhere in the module (no semantic model), so a
///   diagnostic would either nag permanently or not fire at all. The doc
///   comment costs nothing once the extension exists.
/// - The attached type gets the mechanical delegation for free: `var body: some
///   View { self.statelessNode }` for `View`, or `func body(content: Content) ->
///   some View { content.modifier(self.statelessNode) }` for `ViewModifier`.
///
/// The `ViewModifier` case goes through `View.modifier(_:)` specifically —
/// verified directly that forwarding `content` straight into `StatelessNode`'s own
/// `body(content:)` instead does *not* compile: `ViewModifier.Content` is
/// `typealias Content = _ViewModifier_Content<Self>`, a generic struct keyed on
/// the *conforming type itself*, so the attached type's own `Content` and
/// `StatelessNode`'s are two different concrete types no constraint can unify
/// (`error: arguments to generic parameter 'Modifier' ('VM' and 'VM.StatelessNode')
/// are expected to be equal`). `.modifier(_:)` sidesteps that entirely — it only
/// needs its argument to conform to `ViewModifier`, not to share a `Content`.
///
/// **This detection is syntactic, not semantic — it reads the literal
/// inheritance clause written on the attached declaration itself.** Macros never
/// get a type checker, so this can't see: conformance declared in a *separate*
/// extension elsewhere in the file/module, conformance via a typealias or
/// protocol composition, or a qualified spelling (`SwiftUI.View`). Only a bare
/// `View`/`ViewModifier` identifier directly on the attached type is recognized.
@attached(member, names: named(StatelessNode), named(statelessNode), named(body))
public macro StatelessNode() =
    #externalMacro(module: "ValueFlowMacros", type: "StatelessNodeMacro")
