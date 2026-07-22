/// Generates a nested `Core` struct — always internal, regardless of the
/// attached type's own access level, and carrying no `@Flowable` — the
/// host's standalone, directly-constructible twin. Two ingredients:
///
/// 1. **Fields** — the same field set as `@Flowable`'s `OutFlow`/`outFlow`,
///    in exactly two kinds: *mapped* wrappers substituted with a mockable
///    stand-in (the whitelist below — the only wrappers this package really
///    knows), and everything else — *unknown* — copied verbatim.
/// 2. **A verbatim copy of every non-stored member** — `body`, helper
///    computed properties, methods, `static` members, nested types. Write the
///    host as one completely ordinary SwiftUI view; `Core` carries the
///    identical code, compiled against `Core`'s own fields.
///
/// Initializers are the one member kind *not* copied: `Core` is constructed
/// through Swift's own synthesized memberwise init (in tests/previews, with
/// mocks), and a copied init would suppress that synthesis.
///
/// ```swift
/// @Shell
/// struct Card: View {
///     @Query private var items: [Item]
///     @State private var isExpanded: Bool = false
///     let title: String
///
///     var body: some View { ... }   // ordinary SwiftUI, written once
///
///     // generates:
///     // struct Core: View {
///     //     @QueryCore var items: [Item]
///     //     @Binding var isExpanded: Bool
///     //     let title: String
///     //     var body: some View { ... }   <- the same text, copied
///     // }
/// }
///
/// // a test or preview constructs the twin directly, no live view needed —
/// // the @QueryCore field's init parameter is the bare fetched value:
/// // Card.Core(items: [item], isExpanded: .constant(true), title: "t")
/// ```
///
/// ## The transform rules, all three of them
///
/// **Rule 1 — no wrapper** (plain `let`/`var`): `var name: T [= default]` —
/// the initial value is kept, so its memberwise parameter comes defaulted;
/// `public` is stripped. (A *private* plain field is a compile error — pure
/// data flow has no room for opaque private state.)
///
/// **Rule 2 — the mapping whitelist**, the only wrappers this macro really
/// knows, all required private: each is substituted with a mockable
/// stand-in — a test mocks the binding to capture every write the copied
/// body makes:
/// - `@State`/`@AppStorage`/`@SceneStorage` → `@Binding var name: T` — their
///   own storage only installs inside a live SwiftUI view; all three share
///   this substitution since each one's `projectedValue` genuinely *is*
///   `Binding<T>` (verified directly, `@SceneStorage` included).
/// - `@Query` → `@QueryCore var name: T` — this package's own drop-in stand-in
///   (see `QueryCore.swift`), one-to-one with the live wrapper's instance
///   surface (`wrappedValue`/`fetchError`/`modelContext`, no `projectedValue`
///   — verified directly against the `_SwiftData_SwiftUI` interface),
///   whitelisted for the practical reason that reading a fetched array
///   shouldn't require standing up an entire SwiftData stack. Its
///   `fetchError`/`modelContext` params both default, so the field's
///   memberwise-init parameter is the *bare* fetched value — `Core(name:
///   [item], …)`, no `QueryCore` spelling at the call site; seed
///   the metadata fields via `m.raw_name = QueryCore(wrappedValue: [item],
///   fetchError: err)` when a test does care.
/// - (`@ViewBuilder` — a result-builder attribute, not a property wrapper —
///   rides along as init machinery: kept for the
///   stored-*closure* form, where it buys real builder syntax at `Core`'s
///   init call site; dropped for the stored-*value* form, where it would
///   make the synthesized init wrap the parameter in a builder closure to no
///   benefit — verified directly.)
///
/// **The whitelisted wrappers must be private** — enforced with a diagnostic
/// (`sourceOfTruthMustBePrivate`, `StoredProperty.swift`): they're a view's
/// own source of truth, never something a caller supplies (that's what
/// `@Binding` is for). Conversely `@Binding`/`@ViewBuilder` must NOT be
/// private — a caller supplies them through the generated init.
///
/// The whitelist is exactly the wrappers where a substitution buys a REAL
/// mock, and nothing else. `@FocusState`/`@AccessibilityFocusState` were
/// once here and got cut: their `.Binding` projections have no public
/// initializer — a test can't back one with its own closures — and their
/// writes no-op outside a live view anyway (verified directly), so the
/// substitution was a pass-through pretending to be a mock; as rule-3
/// verbatim copies they behave identically when hosted.
///
/// **Rule 3 — any other wrapper**, `@Binding` included (it needs no case of
/// its own: the verbatim copy of `@Binding var x: T` already *is* the mock
/// vehicle — `Binding(get:set:)` in a test captures every write): the whole
/// declaration is copied onto `Core` byte-for-byte — attribute (arguments
/// included) and default value kept, `private` kept, `public` erased.
/// Whatever lives in the attribute's own arguments (a `reset:` closure, a
/// key path, a `relativeTo:`) rides along with nothing to reconstruct —
/// proved live by `TrickyDragCardUITests` in the ExampleApp: an earlier
/// design reconstructing `@GestureState var` from just the bare wrapper name
/// silently swapped a custom reset closure for the default one.
///
/// A private rule-3 copy is self-initializing by construction (the host
/// compiled without an init assigning it), so it drops out of `Core`'s
/// memberwise init and produces its value live instead: an `@Environment` copy reads the real
/// environment *reactively* when `Core` is hosted (mock it there via
/// `.environment(...)`, the wrapper's own native story) and the default
/// `EnvironmentValues` outside a live view; a `@GestureState` copy starts a
/// fresh gesture at its declared default. A non-private rule-3 copy stays a
/// memberwise parameter of the wrapper's own type.
///
/// **Every NON-private wrapper field of `Core` carries a `raw_name`
/// accessor (`@RawProperty`)** over its private backing storage — the
/// whitelisted substitutes (always non-private on `Core`) and non-private
/// verbatim copies — so the wrapper *instance* itself can be swapped
/// (`var m = Core(...); m.raw_isOn = .constant(false)`), and every field
/// is `var`. Private verbatim copies get no `raw_` — sealed: not init
/// parameters, not readable, not mocked, they just behave. One access
/// check, no per-wrapper knowledge.
///
/// The copy compiles on both types by construction — the whitelisted fields
/// were designed for read-surface parity (`$x` is `Binding<T>` on both sides
/// for `@State`/`@AppStorage`/`@SceneStorage`, `@Query`'s fetched value
/// reads directly on both via
/// `@QueryCore`), and a verbatim-copied field trivially reads the same on
/// both sides, because it *is* the same declaration. One source text,
/// compiler-copied: the live view runs against the real wrappers with no
/// substitution layer, `Core` is the mockable twin, and drift between them
/// is impossible. Since the host's `body` is hand-written source,
/// `#Preview { Card() }` works natively (macro-*generated* names are
/// invisible inside `#Preview` — a Swift-level rule; previewing `Core` itself
/// in a mocked state still needs a `PreviewProvider`).
///
/// Members declared in a *separate extension* of the host aren't seen (a
/// macro only receives the attached declaration's own syntax) and simply
/// don't appear on `Core` — declare everything `Core` needs directly in the
/// type, or extend `Core` too.
///
/// Independent of `@Flowable` — works with or without it attached.
///
/// ## Why `Core` exists alongside `OutFlow`
/// `OutFlow` is a tuple — structurally convenient, but tuples can't conform to
/// protocols (verified directly: `error: type '(...)' cannot conform to
/// 'Equatable' — only concrete types such as structs, enums and classes can
/// conform to protocols`). `Core` is a real nominal struct capturing the
/// same data, so it can — and it can carry copied members, which a tuple
/// never could.
///
/// ## Why `Core` is always internal, and carries no `@Flowable`
/// `Core` is a testing/preview seam, not API surface — even when the host is
/// `public`, consumers never need the twin; only the module's own tests do
/// (same module, or `@testable import`). Verbatim-copied fields keep
/// whatever access the host declared, `private` included; every mapped field
/// is internal. Swift's memberwise-init synthesis reproduces every
/// field-specific behavior `@Flowable` would generate by hand — verified
/// directly: a property-wrapper field with no `init(wrappedValue:)`
/// (`@Binding`) synthesizes a parameter of the
/// *wrapper's* type, one that does (`@QueryCore`, `@Bindable`) synthesizes a
/// parameter of the *wrapped* type, and `@ViewBuilder` directly on a stored
/// `let` synthesizes a real builder parameter for the stored-closure form.
///
/// ## Automatic `View`/`ViewModifier` detection
/// When the attached type's own inheritance clause spells `View` or
/// `ViewModifier`, `Core` is declared to conform to the same protocol —
/// satisfied by the copied `body`/`body(content:)`. For `ViewModifier`, the
/// copied `body(content:)`'s `Content` resolves to `Core`'s *own*
/// `ViewModifier.Content` — a different concrete type from the host's
/// (`typealias Content = _ViewModifier_Content<Self>`, keyed on the
/// conforming type itself — verified directly), which is fine: each type
/// satisfies the protocol independently.
///
/// **Detection is syntactic, not semantic — it reads the literal inheritance
/// clause written on the attached declaration itself.** Macros never get a
/// type checker, so conformance declared in a separate extension, via a
/// typealias or protocol composition, or spelled qualified (`SwiftUI.View`)
/// is invisible. Only a bare `View`/`ViewModifier` identifier directly on the
/// attached type is recognized.
@attached(member, names: named(Core))
public macro Shell() =
    #externalMacro(module: "CoreFlowMacros", type: "ShellMacro")
