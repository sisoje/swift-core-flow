/// Generates a nested `Core` struct — always internal (the struct,
/// every field, and the `core` property itself), regardless of the
/// attached type's own access level, and carrying no `@DataLayout` — plus a
/// `core` computed property building one from the current instance.
/// Shares its constructed-field set with `@DataLayout`'s own `OutFlow`/
/// `outFlow`, plus `@Environment`/`@Namespace` (which `OutFlow` deliberately
/// leaves out — see its own doc comment — but `Core` still
/// captures): every non-private participating property, plus private
/// `@Environment`/`@Query`/`@State`/`@AppStorage`/`@SceneStorage`/`@FocusState`/
/// `@Namespace` state, each captured once as a plain value when
/// `.core` is computed.
///
/// Independent of `@DataLayout` — doesn't replace `OutFlow`/`outFlow`, and works
/// with or without `@DataLayout` also attached (it collects the type's stored
/// properties itself).
///
/// ```swift
/// @Shell
/// struct Card: View {
///     @Query private var items: [Item]
///     @Environment(\.colorScheme) private var colorScheme: ColorScheme
///     @State private var isExpanded: Bool = false
///     let title: String
///     var subtitle: String?
///     // generates:
///     // struct Core {
///     //     let items: (wrappedValue: [Item], fetchError: Error?)
///     //     let colorScheme: ColorScheme
///     //     @Binding var isExpanded: Bool
///     //     let title: String
///     //     let subtitle: String?
///     // }
///     // var core: Core {
///     //     Core(items: #pick(from: _items, \.wrappedValue, \.fetchError),
///     //               colorScheme: colorScheme, isExpanded: $isExpanded,
///     //               title: title, subtitle: subtitle)
///     // }
/// }
/// ```
///
/// ## Why `Core` exists alongside `OutFlow`
/// `OutFlow` is a tuple — structurally convenient, but tuples can't conform to
/// protocols (verified directly: `error: type '(...)' cannot conform to
/// 'Equatable' — only concrete types such as structs, enums and classes can
/// conform to protocols`). `Core` is a real nominal struct capturing the
/// same data, so it can — `Equatable`/`Codable`/a shared "any stateless snapshot"
/// protocol are all reachable on it in a way they never can be on `OutFlow`.
///
/// ## Why `Core` is always internal, and carries no `@DataLayout`
/// `Core` is a purely internal testing/snapshot seam — `.core`
/// for assertions, plus a `Core`-hosted `body`/`body(content:)`
/// implementation — not part of the attached type's public API, even when
/// that type itself is `public`: consumers of a public host never need the
/// snapshot, only the package's own tests do (reachable from the same module,
/// or a `@testable import`). So the struct, every field, and `core`'s
/// own access are always internal, never mirroring the attached type's access
/// level.
///
/// No hand-rolled init is needed either. Swift's own memberwise-init synthesis
/// already reproduces every field-specific behavior `@DataLayout` would generate
/// by hand — verified directly: a property-wrapper field with no
/// `init(wrappedValue:)` (`@Binding`, `@FocusState<T>.Binding`) synthesizes a
/// parameter of the *wrapper's* type, one that does (`@Bindable`) synthesizes a
/// parameter of the *wrapped* type, and `@ViewBuilder` directly on a stored
/// `let` synthesizes a real builder parameter for the stored-closure form
/// (see below) — exactly what `@DataLayout` would hand-write. The one thing
/// genuinely lost by skipping `@DataLayout` is `InFlow`/`InFlowSplat`/`inFlow`/`makeFlow(_:)` on
/// `Core` itself, accepted since nothing here needs to round-trip a
/// snapshot back into itself.
///
/// Because `Core`'s own type is always internal, `core`'s
/// access is forced internal too — Swift rejects a more-accessible property
/// with a less-accessible type (verified directly: "property must be declared
/// internal because its type uses an internal type"). `body`/`body(content:)`
/// on the *attached* type, by contrast, still mirrors that type's own access
/// (`public` included) — verified directly that this compiles even though it
/// reads `core` (internal) and returns it: `some View`'s opaque
/// return type only exposes the `View` conformance, never the concrete
/// `Core` type, so a `public` `body` can freely return an internal
/// concrete value.
///
/// ## Every source-of-truth wrapper becomes a plain, constructed value
/// `@Query`, `@State`/`@AppStorage`/`@SceneStorage`/`@FocusState`, and
/// `@Environment`/`@Namespace` all become ordinary fields on `Core`,
/// captured once (as a plain value, read once when `.core` is
/// computed) rather than kept live — never the original attribute, except
/// `@Binding`/`@FocusState<T>.Binding` (below), which are deliberate
/// substitutions:
/// - `@Query` → the synthesized `(wrappedValue:, fetchError:)` tuple, no
///   attribute — built via `#pick` (this package's own `TuplePicker` macro),
///   picking those two real members verbatim, no renaming. `modelContext` is
///   deliberately left off: plumbing for issuing further queries/saves, not a
///   snapshot value worth asserting on.
/// - `@State`/`@AppStorage`/`@SceneStorage` → `@Binding var name: T` — the one
///   case that keeps an attribute, substituted rather than mirrored, since
///   their own storage only installs inside a live SwiftUI view and can't be
///   redeclared as itself on a plain struct. All three share this
///   substitution since all three share the same shape (settable
///   `wrappedValue`, `projectedValue` genuinely `Binding<T>` — verified
///   directly, `@SceneStorage` included).
/// - `@FocusState` → `@FocusState<T>.Binding var name: T` — its own
///   substituted attribute, distinct from `@Binding` above. `@FocusState`'s
///   own `projectedValue` is `FocusState<T>.Binding`, **not** `Binding<T>` —
///   verified directly against the real SwiftUI interface: it exposes only
///   `wrappedValue` and `projectedValue` (itself), no conversion to
///   `Binding<T>` and no public initializer either. The real
///   `FocusState<T>.Binding`, though, is itself `@propertyWrapper`-attributed
///   (verified directly), so it redeclares onto `Core` the same way
///   `@Binding` does — just spelling a different wrapper — and round-trips for
///   free: `snap.name` reads the unwrapped value, `snap.$name` hands back a
///   real `FocusState<T>.Binding` usable directly with `.focused(_:)`.
/// - `@Environment`/`@Namespace` → a plain `let name: T`, no attribute at all.
///   Not because the value doesn't change — because the *attribute* can't be
///   preserved: both wrappers' `wrappedValue` is get-only (verified directly
///   for `@Environment`: `error: cannot assign to property: 'colorScheme' is
///   a get-only property`), and the synthesized init always assigns `self.x
///   = x` — a plain, unattributed `let` has no such restriction. Always
///   `let`, not mirroring the original's `let`/`var` (the original is
///   *always* `var`, every property wrapper requires it) — the captured copy
///   is a one-time snapshot, immutable by design. `OutFlow` makes the
///   opposite call and excludes both entirely, since a captured snapshot goes
///   stale (`@Environment`) or has no demonstrated need there
///   (`@Namespace`) — `Core` captures both anyway, for the same
///   reason it treats every field uniformly. `@Namespace` additionally has no
///   `projectedValue` at all (unlike every `Binding`-substituted row above),
///   so a plain `let` is its only option regardless.
///
/// **`@State`/`@Environment`/`@Query`/`@AppStorage`/`@SceneStorage`/
/// `@FocusState`/`@Namespace` must be private** — enforced with a diagnostic
/// (`sourceOfTruthMustBePrivate`, in `StoredProperty.swift`), not
/// accommodated: they're a view's own source of truth, never something a
/// caller supplies (that's what `@Binding` is for), so every renderer can
/// assume all seven are always private, with no "what if it's also public"
/// case to reason about.
///
/// ## The rule for everything else: mirror the attribute and type, never the mutability
/// Every field except `@Query` (and `@Environment`, above) is declared on
/// `Core` with the *original* property's own attribute (if it has one) and
/// declared type — but never its `let`/`var`. `Core` is a deterministic
/// snapshot, so a field is `var` only where Swift's own property-wrapper rule
/// forces it (a genuine `@propertyWrapper` type requires `var` storage; verified
/// directly, `@Bindable let model: Settings` is a compile error: "property
/// wrapper can only be applied to a 'var'"). Everything else — including `@Query`
/// above — is `let`, regardless of what the original property was declared as:
/// - A plain `var subtitle: String?` becomes `let subtitle: String?` on
///   `Core` — a captured value, not a re-tweakable one.
/// - A genuine, already-public `@Binding` field mirrors verbatim into exactly
///   the same `@Binding var name: T` form `@State`/`@AppStorage` are
///   *substituted* into above — same payoff, no extra logic needed for this
///   case specifically. `@Binding` is itself a genuine property wrapper, so it
///   keeps `var`.
/// - `@ViewBuilder` mirroring is a real win here, unlike `OutFlow`'s tuple —
///   but only for the stored-*closure* form (`let content: () -> Content`):
///   the field type is already a closure there, so the attribute is pure
///   upside — real builder syntax at `Core`'s own init call site, not
///   just documentation. For a stored *value* (`let footer: Content`),
///   mirroring the attribute would make Swift's own synthesized init wrap the
///   parameter in a builder closure purely to satisfy it (verified directly)
///   — overhead with no benefit for a value that's already built and just
///   being copied through — so it's dropped there entirely: `footer` stays a
///   plain `let footer: Content`, passed straight through with no wrapping on
///   either side.
/// - `@Bindable` needs no special handling beyond the general "genuine wrapper
///   keeps var" rule above — no init logic here ever recognized `@Bindable`
///   specially even on the *original* type (it just does `self.model = model`,
///   legal since `@Bindable`'s wrappedValue is a plain get/set), so mirroring
///   it onto `Core` works identically under Swift's own synthesized
///   init.
///
/// ## Automatic `View`/`ViewModifier` detection
/// When the attached type's own inheritance clause spells `View` or
/// `ViewModifier` — `struct Card: View` or `struct VM: ViewModifier` — two more
/// things are generated on top of the usual `Core` struct/`core`
/// property:
/// - `Core` is additionally declared `: View` or `: ViewModifier` — a
///   requirement, not an implementation; the real `body`/`body(content:)` is
///   still hand-written, in a separate extension of `Core`. Swift's own
///   "does not conform to protocol" build error enforces that this gets
///   written at all; a doc comment generated on `Core` itself (visible via
///   Quick Help/jump-to-definition) says exactly what to write and where —
///   not a diagnostic, since the macro can't know whether the extension
///   already exists elsewhere in the module (no semantic model), so a
///   diagnostic would either nag permanently or not fire at all. The doc
///   comment costs nothing once the extension exists.
/// - The attached type gets the mechanical delegation for free: `var body: some
///   View { core }` for `View`, or `func body(content: Content) ->
///   some View { content.modifier(core) }` for `ViewModifier`.
///
/// The `ViewModifier` case goes through `View.modifier(_:)` specifically —
/// verified directly that forwarding `content` straight into `Core`'s own
/// `body(content:)` instead does *not* compile: `ViewModifier.Content` is
/// `typealias Content = _ViewModifier_Content<Self>`, a generic struct keyed on
/// the *conforming type itself*, so the attached type's own `Content` and
/// `Core`'s are two different concrete types no constraint can unify
/// (`error: arguments to generic parameter 'Modifier' ('VM' and 'VM.Core')
/// are expected to be equal`). `.modifier(_:)` sidesteps that entirely — it only
/// needs its argument to conform to `ViewModifier`, not to share a `Content`.
///
/// **This detection is syntactic, not semantic — it reads the literal
/// inheritance clause written on the attached declaration itself.** Macros never
/// get a type checker, so this can't see: conformance declared in a *separate*
/// extension elsewhere in the file/module, conformance via a typealias or
/// protocol composition, or a qualified spelling (`SwiftUI.View`). Only a bare
/// `View`/`ViewModifier` identifier directly on the attached type is recognized.
@attached(member, names: named(Core), named(core), named(body))
public macro Shell() =
    #externalMacro(module: "ValueFlowMacros", type: "ShellMacro")
