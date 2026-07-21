# CLAUDE.md

A small, growing collection of independent Swift macros (plus `Reflector`, a small
non-macro addition that pairs with `@DataLayout`), all in ONE package/target
pair — not one target per macro. Consumers add a single dependency
(`.product(name: "ValueFlow", package: "ValueFlow")`) and get every macro; adding a
new macro is "add a file to each of two targets," not "add a product + three targets
to Package.swift." (An earlier revision split every macro into its own
declaration/plugin/test/product target set — deliberately flattened back to this
shape because the ceremony-per-macro wasn't worth the per-macro dependency
granularity nobody needed.)

- Build/test: `swift build && swift test`
- Format: `swift format --in-place --recursive Sources Tests`
- Examples: `Sources/Examples/main.swift` — one playground, imports and exercises every
  macro in the package. `swift run Examples`.

Targets Swift 6.3 (`swift-tools-version: 6.3`); swift-syntax `600.0.0..<700.0.0`, whose
APIs are stable across the whole Swift 6.x line. Swift 6 language mode (strict
concurrency) throughout.

## Package layout

| Target | Kind | Contents |
|---|---|---|
| `ValueFlowMacros` | macro plugin | every macro's implementation, one `@main` `CompilerPlugin` listing all of them. One file per macro (`DataLayoutMacro.swift`, `StatelessNodeMacro.swift`, `CapabilityMacro.swift`, `PickMacro.swift`), plus shared stored-property collection + rendering (`StoredProperty.swift`, `MemberMacroEntry.swift`, `FieldRendering.swift`, `DataLayoutRendering.swift`) that `@DataLayout` builds on and `@StatelessNode` reuses (`StatelessNodeRendering.swift`), and TuplePicker's own parsing (`KeyPathPick.swift`, `TuplePickerSupport.swift`) |
| `ValueFlow` | library (the one product) | every macro's public attribute/expression declaration, one file per macro (`DataLayout.swift`, `StatelessNode.swift`, `Capability.swift`, `TuplePicker.swift`), plus `Reflector.swift` — a small non-macro addition that pairs with `@DataLayout` (see below) |
| `ValueFlowTests` | test (XCTest + swift-testing, same target) | all coverage: `assertMacroExpansion` per macro, plus TuplePicker's and Reflector's real-compiled end-to-end suites |
| `Examples` | executable | combined playground for every macro (and Reflector) |

Adding a new macro: one new file in `ValueFlowMacros` for the implementation
(`Foo­Macro: MemberMacro`/`ExpressionMacro`), add it to `Plugin.swift`'s
`providingMacros`, one new file in `ValueFlow` for the public
`@attached`/`@freestanding` declaration pointing `#externalMacro(module:
"ValueFlowMacros", type: "FooMacro")`, a new `XCTestCase`/`@Suite` in
`ValueFlowTests`, and a `// MARK: -` section in `Examples/main.swift`. No new
Package.swift targets or products. If the macro generates something from a type's
stored properties (like `@DataLayout` does), build it on `StoredProperty.swift`'s
collection (`validatedProperties` in `MemberMacroEntry.swift`) and
`DataLayoutRendering.swift`'s functions rather than re-deriving them —
everything being one module is exactly what makes that free (no cross-target
`public`, no extra target wiring).

This package has gone through a few macro-boundary redesigns worth knowing about if
you're extending it further:

- **`@DataLayoutInit` used to be its own macro** — an init taking every stored
  property as one tuple-typed parameter, plus the `InFlowSplat` typealias
  describing that tuple. It's gone as a standalone macro now: the typealias half
  was folded directly into `@DataLayout` (every `@DataLayout` type gets an
  `InFlowSplat` typealias alongside its init, for free), and the "one tuple
  *parameter*" half was dropped entirely rather than carried over —
  `@DataLayout`'s own init is unchanged, `InFlowSplat` is declared but nothing
  consumes it as a single init argument anymore. If a future macro wants that
  back, `renderInFlowSplatTypealias` in `DataLayoutRendering.swift` already has
  the tuple-vs-bare-type collapse logic to build on.
- **`@DataInit`** generated both `@DataLayout`'s and `@DataLayoutInit`'s
  initializers from one attribute — removed even before `@DataLayoutInit` was (see
  git history for both). If you want a macro that combines what two existing macros
  generate, the lesson from it still applies: collect stored properties **once** and
  call each renderer directly, rather than spelling it as "stack the two existing
  attribute macros" on the same type — stacking works when the two sets of generated
  members don't collide, but it collects (and diagnoses) the same properties once
  per stacked macro.

## @DataLayout — tricky points

`member` macro that writes a memberwise `init` at the type's own access level, for a
struct, class, or actor — plus two typealias/accessor pairs bridging to/from it (an
unlabeled `InFlowSplat` typealias with a `makeFlow(_:)` factory building
`Self` *from* one — splat-friendly construction — and a labeled `InFlow` typealias
with an `inFlow` computed property reading the current instance's data back
*out* — readable/reflectable), plus a wider `OutFlow`/`outFlow` pair (see below).
Entry point: `Sources/ValueFlowMacros/DataLayoutMacro.swift`. Rendering: all six —
`renderDataLayout` (the init), `renderInFlowSplatTypealias`,
`renderInFlowSplatFactory`, `renderInFlowTypealias`,
`renderInFlowProperty`, `renderOutFlowTypealias`, and `renderOutFlowProperty` — live in
`Sources/ValueFlowMacros/DataLayoutRendering.swift`; the last five are called
from inside the first, so one macro expansion always produces all six together (or
just the bare init, if there are zero properties to alias/build from).

The init:
- **Syntax-only, no type inference.** A non-private property that becomes a parameter
  needs an explicit type — `var count: Int = 0`, not `var count = 0` (the latter is a
  compile error). The macro can't read a type off a literal.
- **`private` is the one exclusion rule.** Every `private`/`fileprivate` property is
  dropped from the init (and the typealias). That single rule also keeps SwiftUI's
  view-owned wrappers out — `@State`/`@Environment`/`@StateObject` are always private
  — so there's no per-wrapper allow/deny list.
- **`@Binding` is the kept exception:** threaded as a projected `Binding<T>`, assigned
  `self._x = x`.
- **`@ViewBuilder` has two forms.** Stored closure `let vb: () -> Content` →
  `@ViewBuilder vb: @escaping () -> Content`, `self.vb = vb`. Stored value
  `let vb2: Content` → `@ViewBuilder vb2: () -> Content`, `self.vb2 = vb2()` — the init
  *calls* the builder.
- **Function-typed properties get `@escaping`**, attributed types included
  (`@MainActor () -> Void`, `@Sendable (Int) -> Void`). Optional closures
  (`(() -> Void)?`) get no `@escaping` — already escaping; adding it is a compile error.
- **Optional `var` → `= nil` parameter default** (`T?` and `T!`), mirroring Swift's
  synthesizer — the property is implicitly nil-initialized, no explicit `= nil` needed.
- **No stored `let` constants.** `let version = 1` as a property is *not* special-cased;
  it yields a `let`-reassignment compile error. Use `static let`.
- **Skipped:** computed properties and `static`/`class` members. **Kept:** stored
  properties with only `willSet`/`didSet` observers.
- **Tests are whitespace-sensitive** (`assertMacroExpansion`). On a formatting-only
  failure, paste the "actual" block into `expandedSource`. Diagnostic specs anchor
  `line`/`column` at the property's name, not the line start.

The `InFlowSplat` typealias — same property collection as the init above,
rendered differently:
- **Two or more properties** → an *unlabeled* tuple: `public typealias
  InFlowSplat = (T, U)`, not `(x: T, y: U)`. Deliberate, not an oversight — see
  below.
- **Exactly one property still gets an `InFlowSplat`, just not a tuple.** Swift
  has no 1-tuples — `(x: T)` as a type collapses to plain `T`, no `.x` accessor —
  so `InFlowSplat` aliases the bare field type directly (`typealias
  InFlowSplat = T`).
- **Zero properties** → no typealias at all — there's nothing to alias, and the init
  above already covers the zero-property case on its own (`init() {}`).
- **No per-field defaults.** Tuple element types can't carry `= default`, so an inline
  `var` default and optional-implies-`nil` are both *dropped* here — unlike the init,
  which keeps them.
- **Never `@escaping`, even on function-typed fields.** `@escaping` is only legal
  directly on a function parameter; here the parameter is the tuple (or the collapsed
  single field), so a closure nested inside it is already escaping — same reasoning
  as the init's optional-closure case, just applied to every function-typed field
  instead of only optional ones.
- **`@ViewBuilder` is ignored entirely.** A stored-value field
  (`@ViewBuilder let footer: Content`) keeps its own type (`Content`) in the
  typealias, *not* the `() -> Content` builder the init uses right above it. The init
  wants that wrapping — it's what buys trailing-closure syntax at the call site. That
  reason doesn't exist for a tuple type (no parameter position for a trailing closure
  to attach to), and wrapping would actively hurt: `InFlowSplat` is meant to be
  data you pass around/store/diff, and a closure isn't `Equatable` or comparable.
  `baseTypeText` (in `FieldRendering.swift`) takes a `wrapViewBuilder` flag for
  exactly this — the init's own rendering passes `true` (the default), the typealias
  rendering passes `false`.
- **The init doesn't route through the typealias** — `InFlowSplat` isn't a
  parameter of the init above. It's declared for API uniformity/discoverability
  (every `@DataLayout` type has one to reference, e.g. in generic code) independent
  of the init's own signature.
- **Why unlabeled: verified directly, both ways.** A tuple *value* already bound
  with different labels (`let t = (xxx: 1, yyy: 2)`) fails to convert into a
  *labeled* tuple type of the same shape (`error: cannot convert value of type
  '(xxx: Int, yyy: Int)' to expected argument type '(x: Int, y: Int)'`), but
  succeeds once the target is unlabeled (`(Int, Int)`) — Swift only enforces label
  agreement between two labeled tuple types, not into an unlabeled one. A labeled
  tuple *literal* (`(x: 1, y: 2)`) converts into an unlabeled target either way, so
  this loses nothing for a caller constructing the value fresh — only a
  pre-existing, differently-labeled variable needed the loosening. Real cost: with
  no labels, the type checker no longer catches two same-typed fields swapped in
  the wrong order.

The `makeFlow(_:)` factory — a `static func` (not a second `init`) building
`Self` from an `InFlowSplat`, present exactly when `InFlowSplat` is:
- **A static func, not a delegating `init`, specifically to work uniformly across
  struct/class/actor.** A second `init` calling `self.init(...)` needs the
  `convenience` keyword on a class/actor and drags in Swift's designated/convenience
  init rules; `Self(...)` inside a plain static function sidesteps that entirely.
- **Forwards each field directly** — `Self(x: flow.0, y: flow.1)` — not
  the `[layout].map(Self.init).first!` trick an *unapplied* `Self.init` reference
  needs to accept a tuple positionally. The macro already knows every field's
  position, so it just spells out the call.
- **Fields are read positionally** (`flow.0`, `flow.1`, … in field
  order), since `InFlowSplat` is unlabeled — not by name.
- **A `@ViewBuilder`-stored value is the one field that isn't forwarded as-is.**
  `InFlowSplat` stores it as a plain value (`Content`), but the primary init
  still wants a `() -> Content` builder for it — so `makeFlow(_:)` wraps it back
  into a trivial closure: `footer: { flow.2 }`.
- **Single-property collapse carries through unchanged.** When `InFlowSplat` is
  a bare type (not a tuple), `flow` *is* the one field's value directly — no
  positional index needed: `Self(value: flow)`.
- **Positional, unlabeled parameter (`_ flow:`), not `make(inFlowSplatted:)`** — a
  deliberate naming choice: the factory is spelled `makeFlow(_:)`, called as
  `Type.makeFlow(someFlow)`, not `Type.make(inFlowSplatted: someFlow)`.

The `InFlow` typealias and `inFlow` property — the reverse direction,
present under the same collapse/zero rules as `InFlowSplat` above:
- **`InFlow` is `InFlowSplat`, labeled.** Same fields, same types, same
  1-tuple collapse and zero-properties-means-nothing rules — just
  `(x: Int, y: Int)` instead of `(Int, Int)`. Built by
  `renderInFlowTypealias`, always with `wrapViewBuilder: false` like
  `InFlowSplat` itself, for the same reasons (no tuple parameter position, and a
  closure would make the field non-`Equatable`).
- **Exists for readable access and real `Mirror` support.** Verified directly:
  `Mirror(reflecting:)` reports each field's actual name over a *labeled* tuple, but
  only positional labels (`.0`, `.1`) over an *unlabeled* one — `InFlowSplat`
  alone can't support generic field reflection (see `Reflector` below), `InFlow`
  can.
- **`inFlow` reads every field straight off `self`** via
  `fieldReadExpression` (`FieldRendering.swift`) — `self.x` for everything except
  `@Binding`, which reads its projected form `self._x` to match `InFlowSplat`'s
  `Binding<T>` field type.
- **No `@ViewBuilder` wrapping needed here, unlike `makeFlow(_:)`'s reverse
  direction.** A stored property already holds exactly its own declared type
  regardless of `@ViewBuilder` — that attribute only ever reshapes the *init
  parameter*, never the property's own storage — so every field is just read
  directly, no unwrap/rewrap logic like `makeFlow(_:)` needs for a
  `@ViewBuilder`-stored value.
- **Round-trips through `makeFlow(_:)` with no manual conversion.**
  `Self.makeFlow(someInstance.inFlow)` works as-is — verified directly —
  since an `InFlow` value converts into `InFlowSplat`'s unlabeled parameter
  the same way any differently-labeled tuple does (see "Why unlabeled" above).

`allFieldNames` — **removed.** An earlier revision had a `static var
allFieldNames: [String]` here, unconditionally listing every stored property's
name with no filtering at all (private, unwrapped fields included) — the one
member with no tuple counterpart, since no `InFlowSplat`/`InFlow`/`OutFlow`
captures a totally-private, non-wrapper field like `private var cache = 0`
either. Removed once it was clear `Reflector.fieldNames(of:)` already covers
the same need for any *specific* generated tuple without a dedicated member —
the real gap that removal opens (a plain private field genuinely has no tuple
anywhere to reflect over) was accepted as YAGNI; revisit if it actually comes
up. See the equivalent note in `Sources/ValueFlow/DataLayout.swift`.

`OutFlow`/`outFlow` — a labeled tuple typealias + computed property (`outFlowFieldType`,
`outFlowFieldReadExpression`, `renderOutFlowTypealias`, `renderOutFlowProperty`, all
in `DataLayoutRendering.swift`) wider than `InFlow`/`inFlow`, for
"give me a view's full externally-relevant *capturable* state, not just its
constructor data":

**Why this exists — testability, not just wider read access.** Any SwiftUI node
that owns or reads live state via `@State`/`@Query`/`@AppStorage` introduces a
source of truth (SOT) that only works inside a real render pipeline (view
identity, a live `ModelContext`) — which makes it hard to test directly.
`OutFlow` converts that SOT into a plain, stateless snapshot: construct the
type, read `.outFlow`, assert on the fields — no live view hierarchy required.
That's the actual motivating idea behind targeting exactly these wrapper kinds,
not "read private state too" for its own sake. See
`Tests/ValueFlowTests/OutFlowTests.swift` for this property demonstrated
directly (`outFlowReadsDataLayoutFieldsAndRecognizedPrivateWrappersTogether`
constructs a `Card` and reads `.outFlow.isExpanded`/`.isOn` with no live view
ever installed).

**`@Environment` is deliberately excluded, unlike `@Query`/`@State`/
`@AppStorage`** — not because it's technically uncapturable (a plain,
unattributed value works fine, same as any other field; `@StatelessNode`, below,
captures it exactly that way), but because a captured snapshot goes stale the
instant the real environment changes, and `@Environment`'s own mocking story
(inject a different value where the type is constructed/hosted) already covers
testing it without this package's help. `@StatelessNode` makes the opposite call
and captures it anyway, for the same reason it treats every field uniformly.

- **Field set: `InFlow`'s fields, plus private `@Query`/`@State`/`@AppStorage`
  properties** — `outFlowProperties(_:)` computes this as `properties.filter {
  !$0.isPrivate || $0.isQuery || $0.isStateOrAppStorage }`. Every other private
  property (`private var cache = 0`, `@StateObject`, `@Environment`, …) is
  excluded — `OutFlow` is scoped to exactly `@Query`/`@State`/`@AppStorage`, not
  "every private property."
- **Declaration order, preserved as one interleaved list** — not data-layout fields
  first with wrapper fields appended after. `outFlowProperties` filters
  `properties` (already declaration-ordered) in place, so a `@Query` field declared
  before a plain `public let` one comes first in `OutFlow` too.
- **Two type mappings, both in `outFlowFieldType`**:
  - `@Query` (`isQuery`) → **always** `(result: WrappedType, fetchError:
    Error?, modelContext: ModelContext)`, synthesized — **not** a passthrough of
    the declared type (two earlier revisions got this wrong: first shipped a bare
    passthrough, then a synthesized-but-always-`nil` `fetchError` with no
    `modelContext` at all — both corrected before release). `WrappedType` is the
    property's own declared type — verified in the Examples playground against
    SwiftData's real `@Query private var items: [Item]` → `OutFlow` field
    `items: (result: [Item], fetchError: Error?, modelContext:
    ModelContext)`. `fetchError`/`modelContext` are **real members of the `Query`
    wrapper instance**, not synthesized placeholders — verified directly against
    the SwiftData interface: `@MainActor @preconcurrency public var fetchError:
    (any Error)? { get }`, `public var modelContext: ModelContext { get }`,
    both declared on `Query<Element, Result>` itself (the type `self._items` has).
  - `@State`/`@AppStorage` (`isStateOrAppStorage`) → `Binding<WrappedType>`, since
    these are the view's own externally read-*and-write*-able storage.
  - Everything else (non-private fields) uses `baseTypeText` unchanged — the same
    rule `InFlow` already applies.
- **Matching read-expression mappings, in `outFlowFieldReadExpression`**: `@State`/
  `@AppStorage` read the *projected* value, `self.$x` — **not** `self._x`, which
  gives the wrapper instance itself (`State<T>`, not `Binding<T>`; verified
  directly). `@Query` reads `(result: self.x, fetchError: self._x.fetchError,
  modelContext: self._x.modelContext)` — `self.x` is the wrapper's `wrappedValue`;
  `fetchError`/`modelContext` are read off the wrapper instance itself (`self._x`),
  the same underscore-prefixed access `@Binding` already uses elsewhere in this
  file — genuinely live values, not placeholders. Every non-private field uses
  `fieldReadExpression` unchanged (`self.x`, or `self._x` for a genuine
  `@Binding` field, which really is its own projection).
- **`@Query`/`@State`/`@AppStorage` need an explicit type even though they're
  private** — relaxes the general "private properties are exempt from needing a
  type" exemption specifically for these three, in `collectStoredProperties`
  (`StoredProperty.swift`): `OutFlow` reads their type to build its field, so the
  exemption can't extend to them. (`@Environment` also needs an explicit type,
  for `@StatelessNode`'s sake, even though `OutFlow` itself no longer reads it.) The
  shared diagnostic message was reworded to say "initializer/stateless snapshot"
  to cover both reasons a type might be required.
- **Verified directly that a `@State`-derived `OutFlow` binding doesn't write
  through outside a live SwiftUI view render** — constructing a `@DataLayout` type
  directly in plain code (never installed into a real view hierarchy) and mutating
  `outFlow.someStateField.wrappedValue` silently no-ops instead of persisting. This
  is `@State`'s own behavior (its storage only installs once SwiftUI actually
  renders the view), not a bug in `OutFlow` — a genuine caller-supplied `@Binding`
  field, by contrast, really does write through (it's just a getter/setter pair,
  not tied to view identity). See `OutFlowTests.swift`.
- **`@MainActor` is required on any test suite exercising `outFlow` on a
  `View`-conforming type** — verified directly (a real crash, not a guess): `View`
  conformance implicitly infers `@MainActor` isolation for the whole type, so
  touching its members from a nonisolated swift-testing `@Test` function crosses
  that isolation boundary at runtime and traps (`SIGTRAP`) under Swift 6 strict
  concurrency, even though it merely reads a computed property. A plain top-level
  script (`Examples/main.swift`) doesn't hit this — top-level code in a `main.swift`
  already runs on the main actor.

## @StatelessNode — tricky points

A separate `member` macro from `@DataLayout` — not a mode of it, doesn't replace
`OutFlow`/`outFlow`, can be attached with or without `@DataLayout` also present
(it collects the type's stored properties itself via the same shared
`validatedProperties`). Entry point: `Sources/ValueFlowMacros/StatelessNodeMacro.swift`.
Rendering: `renderStatelessNode`, in `Sources/ValueFlowMacros/StatelessNodeRendering.swift`.

Generates a nested `StatelessNode` struct — always internal, carrying no
`@DataLayout` — plus a `statelessNode` computed property building one from the
current instance, sharing its constructed-field set with `OutFlow`/`outFlow`
(`outFlowProperties`, in `DataLayoutRendering.swift`), *plus* `@Environment`
(which `OutFlow` deliberately leaves out — see above — but `StatelessNode` still
captures, computed with its own filter, not `outFlowProperties`): every
non-private participating property, plus private
`@Environment`/`@Query`/`@State`/`@AppStorage` state, each captured once as a
plain value.

- **Why a second, nominal member alongside `OutFlow`'s tuple at all**: tuples
  can't conform to protocols — verified directly, `type '(x: Int, y: String)'
  cannot conform to 'Equatable' — only concrete types such as structs, enums and
  classes can conform to protocols`. `OutFlow` can never support `Equatable`/
  `Codable`/a shared "any stateless snapshot" protocol for that reason. A real
  nominal struct can, for free, once declared.
- **`StatelessNode` is always internal — the struct itself, every field, and
  `statelessNode`'s own access — regardless of the attached type's own access
  level, and never `@DataLayout`.** This is a purely internal testing/snapshot
  seam (`.statelessNode` for assertions, plus a `StatelessNode`-hosted `body`/
  `body(content:)` implementation), not part of the attached type's public API
  even when that type itself is `public` — consumers of a public host never need
  the snapshot, only the package's own tests do (from the same module, or a
  `@testable import`). No hand-rolled init is needed either: Swift's own
  memberwise-init synthesis already reproduces every field-specific behavior
  `@DataLayout` would — verified directly: a property-wrapper field with no
  `init(wrappedValue:)` (`@Binding`) synthesizes a parameter of the *wrapper's*
  type, one that does (`@Bindable`) synthesizes a parameter of the *wrapped*
  type, and `@ViewBuilder` directly on a stored `let` synthesizes a
  builder-closure parameter for a value-typed field, exactly like
  `@DataLayout`'s own hand-written logic. Because `StatelessNode`'s own type is
  always internal, `statelessNode`'s access is forced internal too — Swift
  rejects a more-accessible property with a less-accessible type (verified
  directly: "property must be declared internal because its type uses an
  internal type"). `body`/`body(content:)` on the *attached* type, by contrast,
  still mirrors that type's own access (`public` included) — verified directly
  that this compiles even though it reads `self.statelessNode` (internal) and
  returns it: `some View`'s opaque return type only exposes the `View`
  conformance, never the concrete `StatelessNode` type, so a `public` `body` can
  freely return an internal concrete value.
- **Every source-of-truth wrapper becomes a plain, constructed value — never
  the original attribute, except `@Binding`/`@State`/`@AppStorage`'s
  substitution.** `@Query` → the synthesized tuple, no attribute. `@State`/
  `@AppStorage` → `@Binding var name: T` (the one case keeping an attribute,
  substituted since their storage can't be redeclared as itself on a plain
  struct). `@Environment` → a plain `let name: T`, no attribute at all — not
  because the value doesn't change, but because the *attribute* can't be
  preserved: `@Environment`'s `wrappedValue` has no public setter (verified
  directly: `error: cannot assign to property: 'colorScheme' is a get-only
  property`), and the synthesized init always assigns `self.x = x`; a plain,
  unattributed `let` has no such restriction. Always `let` for `@Environment`,
  not mirroring the original's `let`/`var` (always `var`, every property
  wrapper requires it) — the captured copy is a one-time snapshot, immutable by
  design.
- **`@State`/`@Environment`/`@Query`/`@AppStorage` must be private — enforced
  with a diagnostic, not accommodated.** `sourceOfTruthMustBePrivate`
  (`StoredProperty.swift`, checked in `collectStoredProperties`) rejects any of
  these four declared non-private: they're a view's own source of truth, never
  something a caller supplies (`@Binding` is for that). Every renderer
  downstream can assume all four are always private with no "what if it's also
  public" case to reason about or test — an earlier revision's field-set
  filters (`!$0.isPrivate || $0.isQuery || …`) technically already handled a
  hypothetical non-private case correctly, but there was no reason to leave
  that door open when it's simply invalid usage.
- **The rule for every other field: mirror the original property's own
  attribute and declared type onto `StatelessNode`, but never its mutability.**
  `StatelessNode` is a deterministic snapshot, so a field gets `var` only where
  Swift's own property-wrapper rule forces it (a genuine `@propertyWrapper`
  type — `@Bindable`, or any other real wrapper — requires `var` storage;
  verified directly, `@Bindable let model: Settings` is a compile error:
  "property wrapper can only be applied to a 'var'"). Everything else,
  including `@Query`'s synthesized tuple, is `let` regardless of what the
  original property was declared as: a plain `var subtitle: String?` becomes
  `let subtitle: String?` on `StatelessNode` — a captured value, not a
  re-tweakable one. `@ViewBuilder` carries across (see next bullet) with `let`
  intact — it's **not** a `@propertyWrapper`, it's a result-builder attribute,
  legal directly on a stored `let` (verified directly: `@ViewBuilder let vb: ()
  -> Text` compiles). `@Bindable` carries across with `var` intact and needs no
  special handling beyond the general "genuine wrapper keeps var" rule — no init
  logic here ever recognized `@Bindable` specially even on the *original* type
  (it just does `self.model = model`, legal since `@Bindable`'s wrappedValue is
  a plain get/set), so mirroring it onto `StatelessNode`'s copy works
  identically under Swift's own synthesized init, with no extra logic here.
- **A genuine `@Binding` field mirrors verbatim into the exact same `@Binding
  var name: T` form `@State`/`@AppStorage` are substituted into above** — it
  already *is* that declaration in the original source, so mirroring it lands
  on the same shape with no extra logic, and Swift's synthesized init picks up
  both cases identically (verified directly).
- **`@ViewBuilder` mirroring is a real win here, unlike `OutFlow`'s tuple.**
  `OutFlow`'s tuple has no parameter position for trailing-closure sugar to
  attach to, so it deliberately strips `@ViewBuilder` down to a bare type.
  Swift's own synthesized init reproduces `@ViewBuilder`'s builder-closure
  parameter for a value-typed field (verified directly), so `@ViewBuilder`
  mirrored onto `StatelessNode`'s field genuinely buys real builder syntax at
  its own init call site — not just documentation. One asymmetry this
  introduces: constructing `StatelessNode` in the `statelessNode` computed property must
  wrap a `@ViewBuilder`-stored-*value* field's already-built value back into a
  trivial closure (`footer: { self.footer }`) — the exact same trick
  `renderInFlowSplatFactory`'s `makeFlow(_:)` already uses for its own reverse
  direction, reusing `isFunctionType` to detect which of `@ViewBuilder`'s two
  forms (stored closure vs. stored value) applies.
- **Zero eligible fields still generates a (near-empty) `StatelessNode`** —
  `struct StatelessNode {}` plus `var statelessNode: StatelessNode {
  StatelessNode() }` — no diagnostic, mirroring `@DataLayout`'s own graceful
  zero-property `init()` rather than `@Capability`'s "zero is an error" stance;
  an empty statelessNode snapshot is a sensible, if trivial, concept (Swift
  synthesizes the empty `init()` here on its own, same result).
- **Automatic `View`/`ViewModifier` detection, off the attached type's own
  inheritance clause** (`detectHostKind`, in `StatelessNodeMacro.swift`): `struct
  Card: View` or `struct VM: ViewModifier` gets two members beyond the usual
  pair — `StatelessNode` is additionally declared `: View`/`: ViewModifier` (a
  requirement only; the real `body`/`body(content:)` is still hand-written, in a
  separate extension of `StatelessNode`), and the attached type gets the mechanical
  delegation for free: `var body: some View { self.statelessNode }`, or `func
  body(content: Content) -> some View { content.modifier(self.statelessNode) }`.
  - **Discoverability of the hand-written half is a doc comment, not a
    diagnostic** — a `///` comment generated directly on the `StatelessNode` struct
    declaration (only when `hostKind != .none`) states exactly what to write
    and where, visible via Quick Help/jump-to-definition. Deliberately not a
    compiler diagnostic: the macro has no semantic model, so it can never know
    whether the implementing extension already exists elsewhere in the module
    — a `.note`/`.warning` would either nag permanently (never clears once
    implemented) or not fire at all. A doc comment has no such cost; Swift's
    own "does not conform to protocol" build error already enforces that the
    extension gets written at all, this only clarifies *what* to write, since
    that error alone doesn't say "extend `StatelessNode`, not the outer type."
  - **Syntax-only, not semantic — verified against the exact pinned dependency**:
    `DeclGroupSyntax` (what `StatelessNodeMacro.expansion` receives) exposes
    `inheritanceClause` directly, confirmed by reading the actual
    `.build/checkouts/swift-syntax` source at the resolved `603.0.2`. Detection
    reads that clause for a bare `View`/`ViewModifier` identifier — the same
    textual style `propertyWrapperName` already uses for property wrappers. It
    can't see conformance declared in a separate extension, via a typealias or
    protocol composition, or a qualified spelling (`SwiftUI.View`) — a macro
    never gets a type checker.
  - **The `ViewModifier` case goes through `View.modifier(_:)`, not a direct
    `content` forward, for a verified reason**: `ViewModifier.Content` is
    `typealias Content = _ViewModifier_Content<Self>`, a generic struct keyed on
    the *conforming type itself* — `VM.Content` and `VM.StatelessNode.Content` are
    different concrete types no constraint can unify (`error: arguments to
    generic parameter 'Modifier' ('VM' and 'VM.StatelessNode') are expected to be
    equal`, reproduced directly against the real compiler both as a minimal
    repro and against this exact generated code). `.modifier(_:)` only needs its
    argument to conform to `ViewModifier`, not to share a `Content` — sidesteps
    the whole problem.
- See `Tests/ValueFlowTests/StatelessNodeTests.swift` for this demonstrated
  end-to-end (including the `@MainActor` requirement on any test suite
  exercising `statelessNode` on a `View`-conforming type — same reasoning as
  `OutFlow`'s equivalent note above) and
  `Tests/ValueFlowTests/StatelessNodeSyntaxTests.swift` for the expansion shape,
  including the host-kind-detection cases and the negative case (conformance in
  a separate extension isn't detected).

## @Capability — tricky points

`member` macro that bundles every eligible *computed* property/method into a
`Capability` typealias + `capability` computed property. Entry point + collection +
rendering all live in `Sources/ValueFlowMacros/CapabilityMacro.swift` — doesn't
share `StoredProperty.swift`'s model at all (that's for *stored* properties; this
macro is deliberately about the opposite thing, and mixes properties with methods,
which `StoredProperty` has no concept of).

- **Works on an extension, unlike `@DataLayout` — and that's not an oversight on
  its part.** `@DataLayout` collects *stored* properties, and extensions can
  never declare those, so there's nothing it could ever find there. `@Capability`
  collects *computed* members, which extensions declare freely — so it's useful on
  an extension specifically, and works identically attached directly to the
  struct/class/actor itself.
- **Collects:** computed properties (`var x: Int { ... }` — needs an explicit type,
  same syntax-only reasoning as the other macros) and instance methods (their
  closure type is built from parameter types with labels dropped, `async`/`throws`
  effects, and return type, defaulting to `Void`).
- **Skipped:** `private`/`fileprivate`, `static`/`class`, stored properties
  (including willSet/didSet-only ones), initializers, subscripts, and `mutating`
  methods — Swift can't form a plain closure reference to a mutating method on a
  value type (`error: cannot reference 'mutating' method as function value`,
  verified directly), so including one would generate code that doesn't compile.
- **One eligible member collapses `Capability` to its bare type/value**, same
  1-tuple collapse `@DataLayout`'s `InFlowSplat` typealias does. **Zero** is a
  diagnostic, not an empty tuple — there's no sensible "empty capability."
- **Deliberately no `@Sendable`** on the generated closure fields. Verified directly
  both ways: marking them unconditionally makes the generated code fail to compile
  for any type capturing something non-Sendable (`error: converting non-Sendable
  function value to '@Sendable () -> Void' may introduce data races`), while
  omitting it still compiles fine *and* still permits genuine cross-actor/`Task`
  usage — Swift 6's region-based Sendable checking runs at the point the tuple
  literal is built, independent of the field's declared type.
- **Generic methods work** as long as the tuple field type doesn't leak the bare
  generic parameter name (contextual inference specializes the reference) — not
  specially handled, just documented; a method whose signature's own text would
  require the placeholder to resolve outside its generic scope is a known,
  unguarded limitation.

## #pick (TuplePicker) — tricky points

`expression` macro: `#pick(from: value, \.a, \.b)`. One implementation (`PickMacro`)
behind three arity-generic overloads (one/two/three `from:` sources), all reading the
same flat, `from:`-labeled argument list. Impl:
`Sources/ValueFlowMacros/PickMacro.swift`, `KeyPathPick.swift`.

- **Labels are cosmetic, not static.** The declared return type is a parameter pack
  (`repeat each V1`, concatenated per source), which can't carry per-element labels —
  so a multi-pick result is accessed by index (`.0`, `.1`), not by field name, even
  though the expansion body builds a labeled tuple internally.
- **Renaming a single field needs a real expression, not an argument label.**
  `#pick(from: store, total: \.limit)` cannot work — argument-label matching happens
  against the *declared* parameter list, and a pack parameter is one parameter however
  many arguments it expands to. The `=>` operator (`\.limit => "total"`) is a real
  expression of the same `KeyPath` type, so it type-checks normally; `#pick` reads its
  syntax at expansion time and never evaluates it.
- **`from:` is different from `total:` above** — it's a real, predeclared parameter
  label repeated once per source in the signature, marking the boundary *between* two
  separate pack parameters. That's a legal, verified pattern; an arbitrary caller-chosen
  label on one pack element is not.
- **A value repeated across `from:` groups is bound once**, in order of first
  appearance (`__v0`, `__v1`, …), not re-evaluated per group.
- **Works on bare tuple values**, not just structs/classes — tuple `KeyPath`s are live
  on this toolchain. If targeting an older Swift toolchain, verify this holds there
  first (see the TuplePicker section of the README).
- **Can't nest two `#pick` calls that resolve to the *same* declared overload** as one
  expression (`error: recursive expansion of macro 'pick(from:_:)'`) — split into two
  statements instead. Nesting across *different* arities (one-source result feeding a
  two-source call) does work; the recursion guard keys on the resolved overload, not
  the shared implementation type or the spelled macro name.
- **Duplicate output labels are a compile error** with a Fix-It suggesting a rename.

## Reflector — tricky points

`Sources/ValueFlow/Reflector.swift`. Not a macro — a plain runtime `enum` with one
static generic function, `fieldNames<T>(of: T.Type) -> [String]`, kept in this
package because it's a small, natural companion to `@DataLayout`'s generated members
rather than because it needs code generation of its own. No paired
`ValueFlowMacros` file, no `@attached`/`@freestanding` declaration — it's ordinary
Swift, so it doesn't follow the "one file per macro, two targets" pattern the rest of
this doc describes.

- **Needs only a type, no instance**: `Reflector.fieldNames(of: Point.self)` works
  off `Point.self` alone. It allocates one *uninitialized* `T` via
  `UnsafeMutablePointer<T>.allocate(capacity: 1)` and reads `Mirror(reflecting:
  p.pointee).children.compactMap(\.label)` — safe here specifically because it only
  ever touches `.label`, never `.value`. `Mirror`'s labels come from `T`'s
  compile-time field-descriptor metadata; a child's *value* is only lazily
  materialized (and ARC-retained, for a class-typed field) if you actually access
  `.value`, which this function never does.
- **Requires a value type — enforced at runtime, not compile time**, via
  `precondition(!(T.self is AnyClass), ...)`. Swift has no generic constraint for
  "not a class" to enforce this statically, and a marker-protocol workaround
  wouldn't help either since tuples can't conform to protocols at all — verified
  directly that `View` has exactly the same gap (a `final class` conforms to `View`
  and compiles fine; SwiftUI's "views are structs" is convention, not
  compiler-enforced).
- **The crash this guards against is about `T`'s own top-level kind, not its
  fields** — verified directly, both ways. A bare class as `T`
  (`Reflector.fieldNames(of: SomeClass.self)`) crashes with a null-pointer trap:
  `Mirror` has to cast the top-level reflected value to `CustomReflectable` before
  looking at any field, and that cast needs a valid reference, which uninitialized
  memory read as a class reference isn't. A **struct** containing a class-typed (or
  closure, or array) field is fine — same uninitialized-memory read, but `Mirror`
  never needs to validate/retain that child to report its label.
- **Pairs with `@DataLayout`** by pointing it at `InFlow`, not `InFlowSplat`:
  `Reflector.fieldNames(of: Point.InFlow.self)` reports real field names
  (`["x", "y"]`) because `InFlow` is labeled; the same call against
  `InFlowSplat` would report positional labels (`[".0", ".1"]`) instead, since
  `InFlowSplat` is deliberately unlabeled (see `@DataLayout` above) — not a bug,
  just the wrong typealias for this use.
- **A top-level `private`/`fileprivate` type still restricts its own generated
  members' access to itself** — a `private struct Point` inside a test file means
  `@DataLayout`'s generated `InFlow` is `private` too, which is scoped to
  `Point`'s own body/extensions, *not* file-wide like a top-level `private`
  declaration is. Reaching `Point.InFlow` from elsewhere in the same file
  needs `Point` to not be `private` (or the reference to live inside `Point`
  itself/an extension of it).

