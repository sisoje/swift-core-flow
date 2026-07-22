/// Generates a nested `Core` struct — always internal, regardless of the
/// attached type's own access level, and carrying no `@Flowable` — the
/// host's standalone, directly-constructible twin. Two ingredients:
///
/// 1. **Substituted fields** — the same field set as `@Flowable`'s
///    `OutFlow`/`outFlow` (every non-private participating property, plus
///    every recognized private source-of-truth wrapper), each source-of-truth
///    wrapper replaced with a plain, mockable stand-in (mapping table below) —
///    except `@GestureState`, copied as-is rather than substituted (its own
///    section below).
/// 2. **A verbatim copy of every non-stored member** — `body`, helper
///    computed properties, methods, `static` members, nested types. Write the
///    host as one completely ordinary SwiftUI view; `Core` carries the
///    identical code, compiled against the substituted fields.
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
///     // var core: Core { Core(items: ..., isExpanded: $isExpanded, title: title) }
/// }
///
/// // a test or preview constructs the twin directly, no live view needed:
/// // Card.Core(items: QueryCore(...), isExpanded: .constant(true), title: "t")
/// ```
///
/// The copy compiles on both types by construction — every substituted field
/// was designed for read-surface parity: `$x` is `Binding<T>` on both sides
/// for `@State`/`@AppStorage`/`@SceneStorage`/`@Binding`, `GestureState<T>`
/// on both since `@GestureState` is copied verbatim rather than substituted,
/// `FocusState<T>.Binding` on both, and
/// `@Query`'s fetched value reads directly on both via `@QueryCore`. One
/// source text, compiler-copied: the live view runs against the real
/// wrappers with no substitution layer, `Core` is the stateless twin, and
/// drift between them is impossible. Since the host's `body` is hand-written
/// source, `#Preview { Card() }` works natively (macro-*generated* names are
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
/// (same module, or `@testable import`). Swift's memberwise-init synthesis
/// reproduces every field-specific behavior `@Flowable` would generate by
/// hand — verified directly: a property-wrapper field with no
/// `init(wrappedValue:)` (`@Binding`, `@FocusState<T>.Binding`) synthesizes a
/// parameter of the *wrapper's* type, one that does (`@Bindable`) synthesizes
/// a parameter of the *wrapped* type, and `@ViewBuilder` directly on a stored
/// `let` synthesizes a real builder parameter for the stored-closure form.
///
/// ## The substitution table
/// - `@Query` → `@QueryCore var name: T` — this package's own drop-in stand-in
///   (see `QueryCore.swift`), one-to-one with the live wrapper's instance
///   surface (`wrappedValue`/`fetchError`/`modelContext`, no `projectedValue`
///   — verified directly against the `_SwiftData_SwiftUI` interface).
/// - `@GestureState` → copied verbatim, NOT substituted: `@GestureState
///   private var name: T = default` byte-for-byte (attribute arguments and
///   default kept, `private` kept — it's a pure-UI wrapper `Core` uses
///   as-is). An argument-carrying init (`reset:`/`resetTransaction:`) carries
///   over for free since it lives in the copied attribute text. Because the
///   field stays `private` with a default it drops out of `Core`'s memberwise
///   init and isn't readable from outside `Core` — so the generated `core`
///   property omits it (a captured `Core` starts the gesture fresh at its
///   declared default, not at the host's transient mid-gesture value); mock it
///   through the `@RawProperty` accessor:
///   `m.raw_name = GestureState(wrappedValue: mock)`.
/// - `@State`/`@AppStorage`/`@SceneStorage` → `@Binding var name: T` — their
///   own storage only installs inside a live SwiftUI view; all three share
///   this substitution since each one's `projectedValue` genuinely *is*
///   `Binding<T>` (verified directly, `@SceneStorage` included).
/// - `@FocusState` → `@FocusState<T>.Binding var name: T` — its own
///   substituted attribute, distinct from `@Binding`: `@FocusState`'s
///   `projectedValue` is `FocusState<T>.Binding`, **not** `Binding<T>`, with
///   no conversion between them and no public initializer (verified directly).
///   `FocusState<T>.Binding` is itself `@propertyWrapper`-attributed, so it
///   redeclares like `@Binding` does — `snap.$name` feeds `.focused(_:)`
///   directly.
/// - `@AccessibilityFocusState` → an exact `@FocusState` clone (verified
///   directly — same nested `Binding` shape), same treatment; `snap.$name`
///   feeds `.accessibilityFocused(_:)`.
/// - `@Environment`/`@Namespace`/`@ScaledMetric` → a plain `let name: T` — no
///   attribute; get-only `wrappedValue`, no usable `projectedValue` (verified
///   directly for each). For `@ScaledMetric`, redeclaring would double-scale:
///   its init takes the *base* value, the host reads back the scaled one.
///
/// **Every recognized source-of-truth wrapper must be private** — enforced
/// with a diagnostic (`sourceOfTruthMustBePrivate`, `StoredProperty.swift`):
/// they're a view's own source of truth, never something a caller supplies
/// (that's what `@Binding` is for).
///
/// ## The rule for everything else: mirror the attribute and type
/// Every field is `var`, regardless of the original's `let`/`var` — a
/// captured copy is meant to be re-mocked field by field, and every
/// genuine-wrapper field additionally has a `raw_name` accessor over its
/// private backing storage so the wrapper *instance* can be swapped too:
/// `var m = shell.core; m.raw_isOn = .constant(false)`.
/// A genuine `@Binding` field mirrors verbatim. `@ViewBuilder` (a
/// result-builder attribute, not a wrapper) is mirrored only for the
/// stored-*closure* form, where it buys real builder syntax at the init call
/// site; for the stored-*value* form it would make the synthesized init wrap
/// the parameter in a builder closure purely to satisfy the attribute
/// (verified directly), so it's dropped there. `@Bindable` mirrors with no
/// special handling.
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
@attached(member, names: named(Core), named(core))
public macro Shell() =
    #externalMacro(module: "CoreFlowMacros", type: "ShellMacro")
