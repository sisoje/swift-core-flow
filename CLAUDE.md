# CLAUDE.md

A small, growing collection of independent Swift macros (plus `Reflector`, a small
non-macro addition that pairs with `@Flowable`), all in ONE package/target
pair — not one target per macro. Consumers add a single dependency
(`.product(name: "CoreFlow", package: "CoreFlow")`) and get every macro; adding a
new macro is "add a file to each of two targets," not "add a product + three targets
to Package.swift." (An earlier revision split every macro into its own
declaration/plugin/test/product target set — deliberately flattened back to this
shape because the ceremony-per-macro wasn't worth the per-macro dependency
granularity nobody needed.)

- Build/test: `swift build && swift test`
- Format: `swift format --in-place --recursive Sources Tests`
- Example app: `ExampleApp/project.yml` — ONE real app (xcodegen; the
  generated `.xcodeproj` is gitignored) component-testing the generated
  `Core`s live, via XCUITests. Every scenario hosts a CORE (owning plain
  `@State` for each Binding-typed parameter, or bare `Core()` when there
  are none), one component per scenario, selected via the `EXAMPLE_SCENARIO` env var
  (`ExampleScenario.defaultScenario` when unset, so Cmd-R just works).
  `cd ExampleApp && sh test.sh` runs the suite once — each UI test launches
  its own scenario. Deterministic scenarios use mutation-snapshot testing
  (`SnapshotTestCase` + `Binding.didSet`): the scenario wraps each binding
  it hands to Core with `.didSet { mylog.mylog(name, $0) }`, so every write
  is appended as a `name = value` line to the `SNAPSHOT_LOG` file the
  moment it happens — at the write site, not via a view-layer observer
  replaying history. The first run records `Snapshots/<test>.txt` and
  skips, later runs diff against it — delete the file to re-record.
  Value-streaming scenarios (drag distances) stay predicate-asserted.

Targets Swift 6.3 (`swift-tools-version: 6.3`); swift-syntax `600.0.0..<700.0.0`, whose
APIs are stable across the whole Swift 6.x line. Swift 6 language mode (strict
concurrency) throughout.

## Package layout

| Target | Kind | Contents |
|---|---|---|
| `CoreFlowMacros` | macro plugin | every macro's implementation, one `@main` `CompilerPlugin` listing all of them. One file per macro (`FlowableMacro.swift`, `ShellMacro.swift`, `CapabilityMacro.swift`, `PickMacro.swift`, `RawPropertyMacro.swift`), plus shared stored-property collection + rendering (`StoredProperty.swift`, `MemberMacroEntry.swift`, `FieldRendering.swift`, `FlowableRendering.swift`) that `@Flowable` builds on and `@Shell` reuses (`ShellRendering.swift`), and TuplePicker's own parsing (`KeyPathPick.swift`, `TuplePickerSupport.swift`) |
| `CoreFlow` | library (the one product) | every macro's public attribute/expression declaration, one file per macro (`Flowable.swift`, `Shell.swift`, `Capability.swift`, `TuplePicker.swift`, `RawProperty.swift`), plus two small non-macro additions: `Reflector.swift` (pairs with `@Flowable`, see below) and `QueryCore.swift` (`@Query`.s drop-in stand-in on `Core`/`OutFlow`, see the `@Flowable` OutFlow notes) |
| `CoreFlowTests` | test (XCTest + swift-testing, same target) | all coverage: `assertMacroExpansion` per macro, plus TuplePicker's and Reflector's real-compiled end-to-end suites |

Adding a new macro: one new file in `CoreFlowMacros` for the implementation
(`Foo­Macro: MemberMacro`/`ExpressionMacro`), add it to `Plugin.swift`'s
`providingMacros`, one new file in `CoreFlow` for the public
`@attached`/`@freestanding` declaration pointing `#externalMacro(module:
"CoreFlowMacros", type: "FooMacro")`, and a new `XCTestCase`/`@Suite` in
`CoreFlowTests`. No new Package.swift targets or products. If the macro generates something from a type's
stored properties (like `@Flowable` does), build it on `StoredProperty.swift`'s
collection (`validatedProperties` in `MemberMacroEntry.swift`) and
`FlowableRendering.swift`'s functions rather than re-deriving them —
everything being one module is exactly what makes that free (no cross-target
`public`, no extra target wiring).

This package has gone through a few macro-boundary redesigns worth knowing about if
you're extending it further:

- **`@FlowableInit` used to be its own macro** — an init taking every stored
  property as one tuple-typed parameter, plus the `InFlowSplat` typealias
  describing that tuple. It's gone as a standalone macro now: the typealias half
  was folded directly into `@Flowable` (every `@Flowable` type gets an
  `InFlowSplat` typealias alongside its init, for free), and the "one tuple
  *parameter*" half was dropped entirely rather than carried over —
  `@Flowable`'s own init is unchanged, `InFlowSplat` is declared but nothing
  consumes it as a single init argument anymore. If a future macro wants that
  back, `renderInFlowSplatTypealias` in `FlowableRendering.swift` already has
  the tuple-vs-bare-type collapse logic to build on.
- **`@DataInit`** generated both `@Flowable`'s and `@FlowableInit`'s
  initializers from one attribute — removed even before `@FlowableInit` was (see
  git history for both). If you want a macro that combines what two existing macros
  generate, the lesson from it still applies: collect stored properties **once** and
  call each renderer directly, rather than spelling it as "stack the two existing
  attribute macros" on the same type — stacking works when the two sets of generated
  members don't collide, but it collects (and diagnoses) the same properties once
  per stacked macro.

## @Flowable — tricky points

`member` macro that writes a memberwise `init` at the type's own access level, for a
struct, class, or actor — plus two typealias/accessor pairs bridging to/from it (an
unlabeled `InFlowSplat` typealias with a `makeFlow(_:)` factory building
`Self` *from* one — splat-friendly construction — and a labeled `InFlow` typealias
with an `inFlow` computed property reading the current instance's data back
*out* — readable/reflectable), plus a wider `OutFlow`/`outFlow` pair (see below).
Entry point: `Sources/CoreFlowMacros/FlowableMacro.swift`. Rendering: all six —
`renderFlowable` (the init), `renderInFlowSplatTypealias`,
`renderInFlowSplatFactory`, `renderInFlowTypealias`,
`renderInFlowProperty`, `renderOutFlowTypealias`, and `renderOutFlowProperty` — live in
`Sources/CoreFlowMacros/FlowableRendering.swift`; the last five are called
from inside the first, so one macro expansion always produces all six together (or
just the bare init, if there are zero properties to alias/build from).

The init:
- **Syntax-only, no real type inference — except three unambiguous literal
  kinds.** A property that becomes a parameter needs an explicit type — *unless*
  its inline default is a bare `Bool`/`Int`/`String` literal (`var isOn = false`,
  `var count = 0`, `var label = "x"`), inferred straight off the literal's own
  syntax node kind (`inferredLiteralType`, `StoredProperty.swift`) with no type
  checker involved — same spirit as `@Namespace`'s auto-inferred `Namespace.ID`
  just below. Anything else uninferable (a call, an identifier, `nil`, a
  collection literal, …) still needs an explicit annotation. This also means an
  inline-initialized instance `let` with one of these three literal defaults
  (`let seed = 42`) now gets *past* the missing-type check and fails later, on
  Swift's own `let`-reassignment error instead — see "No stored `let` constants"
  below; the outcome (won't compile) is unchanged, only where the failure
  surfaces.
- **`private` means private, and it must mean something — enforced with
  dedicated diagnostics, not silent exclusion.** A private property with no
  wrapper at all (`private var cache = 0`) used to be silently
  excluded from the init/typealiases, with nothing to show for it in
  `OutFlow`/`Core` either — now it's `plainPrivatePropertyNotAllowed`:
  pure data flow has no room for opaque private state that's neither a source
  of truth nor something a caller supplies. And `@Binding`/
  `@ViewBuilder` — the kinds a *caller* supplies through the generated
  init — are the opposite of source-of-truth state, so declaring one private
  makes it unreachable; that's `callerSuppliedWrapperMustNotBePrivate`
  (`property.isCallerSuppliedWrapper`, `StoredProperty.swift`). Any *other*
  private property just needs *some* wrapper: the mapped source-of-truth set
  (`@State`/`@AppStorage`/`@SceneStorage`/`@Query`,
  `sourceOfTruthMustBePrivate`'s
  domain — those must be private) or any unmapped wrapper (`@Environment`,
  `@GestureState`, `@FocusState`, `@StateObject`, a custom one, …), which carries no
  privacy rule at all — an earlier revision refused unrecognized private
  wrappers outright (`unsupportedPrivateWrapper`, deleted), back when every
  recognized wrapper needed hand-built capture logic; `@Shell`'s
  verbatim-copy default made that gatekeeping pointless.
  `private(set)`/`fileprivate(set)` fall into these same
  diagnostics (the `isPrivate` check matches the keyword regardless of the
  `(set)` detail) — deliberately not special-cased: setter-restricted
  properties have no place in pure data flow either.
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
  (every `@Flowable` type has one to reference, e.g. in generic code) independent
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
  struct/class/actor.** A second `init` calling `init(...)` needs the
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
  `fieldReadExpression` (`FieldRendering.swift`) — `x` for everything except
  `@Binding`, which reads its projected form `$x` to match `InFlowSplat`'s
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
captured a totally-private, non-wrapper field like `private var cache = 0`
(legal at the time) either. Removed once it was clear `Reflector.fieldNames(of:)`
already covers the same need for any *specific* generated tuple without a
dedicated member — the gap that removal opened (a plain private field
genuinely has no tuple anywhere to reflect over) is moot now anyway: that kind
of field is a compile error (`plainPrivatePropertyNotAllowed`, above), not a
silently-excluded one. See the equivalent note in
`Sources/CoreFlow/Flowable.swift`.

`OutFlow`/`outFlow` — a labeled tuple typealias + computed property (`outFlowFieldType`,
`outFlowFieldReadExpression`, `renderOutFlowTypealias`, `renderOutFlowProperty`, all
in `FlowableRendering.swift`) wider than `InFlow`/`inFlow`, for
"give me a view's full externally-relevant *capturable* state, not just its
constructor data":

**Why this exists — testability, not just wider read access.** Any SwiftUI node
that owns or reads live state via
`@State`/`@Query`/`@AppStorage`/`@SceneStorage` introduces a
source of truth (SOT) that only works inside a real render pipeline (view
identity, a live `ModelContext`) — which makes it hard to test directly.
`OutFlow` converts that SOT into a plain, stateless snapshot: construct the
type, read `.outFlow`, assert on the fields — no live view hierarchy required.
That's the actual motivating idea behind targeting exactly these wrapper kinds,
not "read private state too" for its own sake. See
`Tests/CoreFlowTests/OutFlowTests.swift` for this property demonstrated
directly (`outFlowReadsFlowableFieldsAndRecognizedPrivateWrappersTogether`
constructs a `Card` and reads `.outFlow.isExpanded`/`.isOn` with no live view
ever installed).

**No wrapper is excluded, mapped or unknown.** An earlier revision left
`@Environment` out of `OutFlow` on the theory that a captured snapshot goes
stale the instant the real environment changes; a later one refused
*unrecognized* private wrappers with a dedicated diagnostic. Both are gone:
every private wrapper field participates — mapped ones with their mapped
tuple shape, unknown ones as the bare wrapped value — and `OutFlow`'s field
set is identical to `@Shell`'s `Core`'s.

- **Field set: everything** — `outFlowProperties(_:)` is the identity
  function now (kept as the single shared name `renderShell` and the
  `OutFlow` renderers draw from). Nothing reaching it needs filtering: a
  private property with no wrapper (`private var cache = 0`) is refused by
  `collectStoredProperties` (`plainPrivatePropertyNotAllowed`,
  `StoredProperty.swift`), and everything else is legal by construction.
- **Declaration order, preserved as one interleaved list** — not data-layout fields
  first with wrapper fields appended after: `properties` is already
  declaration-ordered, so a `@Query` field declared
  before a plain `public let` one comes first in `OutFlow` too.
- **The type mappings, all in `outFlowFieldType`**:
  - `@Query` (`isQuery`) → **always** `QueryCore<WrappedType>` — this
    package's own drop-in stand-in for the live wrapper
    (`Sources/CoreFlow/QueryCore.swift`, a plain non-macro `@propertyWrapper`
    like `Reflector` is a plain non-macro utility), **not** a passthrough of
    the declared type. One-to-one with the real `Query<Element, Result>`'s
    instance surface — verified directly against the `_SwiftData_SwiftUI`
    interface: exactly `wrappedValue`, `fetchError`, and `modelContext`, and
    **no `projectedValue`**, so `QueryCore` carries the same three members and
    no `$x` projection either. Reading `modelContext` outside a live container
    works — verified directly, no crash — so the eager capture is safe even
    for snapshots built in plain code. An earlier
    revision synthesized a bare `(wrappedValue:, fetchError:)` tuple via
    `#pick` instead (and one before that dropped `modelContext` as
    unexercised plumbing); replaced by the real wrapper so `Core`'s field
    reads the fetched value directly — `core.items`, not
    `.items.wrappedValue` — making body code written against the live
    `@Query` property move onto `Core` unchanged. Both of `QueryCore`'s
    extra init params default — `fetchError` to `nil`, `modelContext` to
    `Environment(\.modelContext).wrappedValue`, the environment's own
    default context, evaluated outside any live view (verified directly, a
    real context, no trap) — since a test mocking a fetched result almost
    never cares about either: `QueryCore(wrappedValue: [item])` just works.
    An init callable with `wrappedValue` alone makes Swift's synthesized
    memberwise init for a `@QueryCore` field take the *bare* value
    (verified directly, locked in by `QueryCoreTests`) — deliberately so:
    tests write `Core(items: [item], title: "t")` with no `QueryCore`
    spelling at all; a directly constructed `Core`'s
    `fetchError`/`modelContext` take the defaults.
    An earlier revision kept `fetchError` required precisely to *prevent*
    this flip, back when `@Shell` generated a `core` capture property that
    passed a fully-constructed `QueryCore` through the memberwise init; both
    the constraint and the capture property itself are gone now.
  - **Every unmapped wrapper needs no case here** — `@Environment`,
    `@GestureState`, `@Namespace`, `@ScaledMetric`, `@StateObject`, a custom
    one, … all fall through to `baseTypeText`: the bare declared type, a
    plain-value snapshot of the current `wrappedValue`, read `x`. (`Core`,
    `@Shell`'s twin, copies an unmapped wrapper's whole declaration verbatim
    instead — `StoredProperty.attributeText`, `renderShell` in
    `ShellRendering.swift`; see the `@Shell` section below.)
  - `@State`/`@AppStorage`/`@SceneStorage` (`isBindingBackedStorage`) →
    `Binding<WrappedType>`, since these are the view's own externally
    read-*and-write*-able storage — all three wrappers' own `projectedValue`
    genuinely *is* `Binding<T>` (verified directly against the real SwiftUI
    interface, `@SceneStorage` included — `wrappedValue` is `{ get nonmutating
    set }`, same shape as `@State`/`@AppStorage`, no separate case needed).
  - `@FocusState`/`@AccessibilityFocusState` → unmapped now, bare wrapped
    value like every other unknown. They were once whitelisted (mapped to
    their own `.Binding` projections); cut because those projections have no
    public initializer — a test can't back one with its own closures — and
    their writes no-op outside a live view anyway (verified directly), so
    the substitution was a pass-through pretending to be a mock.
  - Everything else (non-private fields) uses `baseTypeText` unchanged — the same
    rule `InFlow` already applies.
- **Matching read-expression mappings, in `outFlowFieldReadExpression`**:
  `@Binding`/`@State`/`@AppStorage`/`@SceneStorage` all read the
  *projected* value, `$x` — one shared convention, no `@Binding`-only special
  case (verified directly: `Binding`'s own `projectedValue` is `{ self }`, so
  `$x` gives back the identical `Binding<T>` the backing storage `_x` would,
  write-through included — `_x` survives only on `fieldAssignment`'s side,
  where `$x` is immutable). For `@State`/`@AppStorage`/`@SceneStorage`,
  `$x` is **not** `_x`, which gives the wrapper instance itself
  (`State<T>`, not `Binding<T>`; verified directly). `@Query` reads
  `QueryCore(wrappedValue: _x.wrappedValue, fetchError: _x.fetchError,
  modelContext: _x.modelContext)` — `_x` is the wrapper instance itself
  (`Query<Element, Result>`), the same underscore-prefixed access
  `@Binding`'s *assignment* side uses.
  Every other field — non-private ones, plus every private unmapped wrapper —
  uses `fieldReadExpression` unchanged (`x`, or `$x` for `@Binding`).
- **Every property needs an explicit type**, in `collectStoredProperties`
  (`StoredProperty.swift`) — init parameters obviously, but private wrapper
  fields too: `OutFlow` reads the type to build its tuple field. (The old
  "private properties are exempt" nuance is gone with the wrapper-less
  private fields it existed for.) `@Namespace` is the one exception — it
  needs *no* explicit type at all, since its wrapped type is always
  `Namespace.ID`; see its own note in `StoredProperty.swift`.
- **Verified directly that a `@State`-derived `OutFlow` binding doesn't write
  through outside a live SwiftUI view render** — constructing a `@Flowable` type
  directly in plain code (never installed into a real view hierarchy) and mutating
  `outFlow.someStateField.wrappedValue` silently no-ops instead of persisting. This
  is `@State`'s own behavior (its storage only installs once SwiftUI actually
  renders the view), not a bug in `OutFlow` — a genuine caller-supplied `@Binding`
  field, by contrast, really does write through (it's just a getter/setter pair,
  not tied to view identity). `@SceneStorage` behaves identically
  here — verified directly, same no-op-outside-a-live-view caveat, even though
  it's backed by persistent storage rather than in-memory view
  identity. (The same fact for `@FocusState` is part of why it was cut from
  the whitelist entirely.) See `OutFlowTests.swift`.
- **`@MainActor` is required on any test suite exercising `outFlow` on a
  `View`-conforming type** — verified directly (a real crash, not a guess): `View`
  conformance implicitly infers `@MainActor` isolation for the whole type, so
  touching its members from a nonisolated swift-testing `@Test` function crosses
  that isolation boundary at runtime and traps (`SIGTRAP`) under Swift 6 strict
  concurrency, even though it merely reads a computed property.

## Deliberately unmapped: `@StateObject` / `@ObservedObject`

Neither wrapper is on the mapping whitelist, on purpose, not as a gap to
fill in later. Both are Combine-era `ObservableObject` wrappers —
MVVM/ViewModel-shaped state, exactly what this package's `@Flowable` (plain,
`Equatable`-friendly data) and `@Shell` (mockable stand-ins for the mutating
wrappers) exist to avoid — so they get no mocking stand-in and never will.
Like any unknown wrapper, they're copied onto `Core` verbatim and left
alone; want testable state, model it with the mapped wrappers instead. See
the `swiftui-mv-architecture` skill for the broader argument against
`ObservableObject`/ViewModel patterns in SwiftUI generally.

## @Shell — tricky points

A separate `member` macro from `@Flowable` — not a mode of it, doesn't replace
`OutFlow`/`outFlow`, can be attached with or without `@Flowable` also present
(it collects the type's stored properties itself via the same shared
`validatedProperties`). Entry point: `Sources/CoreFlowMacros/ShellMacro.swift`.
Rendering: `renderShell`, in `Sources/CoreFlowMacros/ShellRendering.swift`.

Generates a nested `Core` struct — always internal, carrying no
`@Flowable` — the host's standalone twin. Three transform rules, in
`renderShell`'s order:
**rule 1**, no wrapper: `var name: T [= default]` — initial value kept (so
the memberwise parameter comes defaulted), `public` stripped;
**rule 2**, the mapping whitelist (`isSubstitutedOnCore`,
`StoredProperty.swift` — the only wrappers this macro really knows, all
required private): the mutating source-of-truth set substituted with
binding-shaped, mockable stand-ins so a test captures every write, plus
`@Query` → `@QueryCore` so reading a fetched array needs no SwiftData stack;
**rule 3**, any other wrapper — `@Binding`, `@Environment`, `@GestureState`,
`@Namespace`, `@ScaledMetric`, `@Bindable`, `@StateObject`, a custom one —
copied verbatim (attribute with arguments and default kept, `private` kept,
`public` erased, via `StoredProperty.attributeText`). Plus a verbatim copy
of every non-stored member (`copiedMemberSources`, `ShellMacro.swift`) —
`body`, helpers, methods, `static` members, nested types. Initializers are
the one member kind *not* copied: `Core` is constructed through Swift's
synthesized memberwise init, and a copied init would suppress it. No `core`
capture property is generated either — an earlier revision emitted
`var core: Core { Core(...) }` off the live host, dragging a whole
per-rule capture-expression mapping with it; deleted, since Core is for
testing and tests construct it directly (a unit test never has a live host
to capture from). The host runs its own hand-written body. Every field is `var`; private verbatim copies are
sealed, they just behave. No `@RawProperty` is stamped anywhere — an
earlier revision decorated wrapper fields with it for instance-swapping on
captured copies; with the capture gone, mocking happens at construction,
and the macro stays in the package as a standalone opt-in for hand-written
code (see `QueryCoreTests`' `FakeCore` for it in use). Mocking the
`Binding`-typed parameters is USE-SITE code, deliberately not generated: a
test backs each with `.constant`, a `Binding(get:set:)` capturing writes
into a local, or a hand-written `@Observable @MainActor` model class whose
`Bindable(model).x` projections mint real write-through bindings in plain
code, no view needed (`handWrittenObservableModelBacksEveryBinding` in
`ShellTests.swift` — note @Observable can't attach to a LOCAL type, so
such a model must be file-scoped). An earlier revision generated exactly
that as a sibling `CoreModel` class (with per-property `didSet` history
logging) plus a `@MainActor static func make(model:...)` wiring
constructor on `Core`; both were cut on the grounds that the few
situational lines they saved belong at the use site, shaped by the test.
Lessons from that era worth keeping if anyone regenerates something like
it: the compiler expands attached macros inside another macro's generated
code just fine (@Binding/@QueryCore today, @Observable then); `@MainActor`
must be explicit on a generated class because a nested type does NOT
inherit the enclosing View-conformance isolation (verified directly); and
a generated observable class must be a SIBLING of `Core`, not nested
inside it — nesting breaks `@Observable`'s extension-macro half, which
type-checks but fails at link with a missing `Observable` conformance
descriptor for the doubly-nested class (one level of macro-generated
nesting is the compiler's limit; both verified directly).
The field set is *identical* to `OutFlow`'s — `renderShell` calls
`outFlowProperties` directly (the identity function now; see
`FlowableRendering.swift`).

The copy is legal because it happens inside `@Shell`'s *own* expansion —
only *cross*-expansion name references are forbidden, the same Swift-level
rule that makes `#Preview` unable to see `Core` or any macro-generated name
(verified directly, five ways; `PreviewProvider` is the escape hatch for
previewing a mocked `Core`, and `#Preview { Card() }` works since the host's
`body` is hand-written source). It compiles on both types because every
field has read-surface parity — designed in for the mapped ones (`$x` is
`Binding<T>` on both sides), trivially true for a
verbatim copy, because it *is* the same declaration. The
copied text is dedented first (`dedented`, `ShellMacro.swift`) — the
expansion machinery re-shifts every line by the splice position, so without
it copies land double-indented. Members in a separate extension of the host
aren't seen (same syntax-only limitation as host-kind detection).

- **Why a second, nominal member alongside `OutFlow`'s tuple at all**: tuples
  can't conform to protocols — verified directly, `type '(x: Int, y: String)'
  cannot conform to 'Equatable' — only concrete types such as structs, enums and
  classes can conform to protocols`. `OutFlow` can never support `Equatable`/
  `Codable`/a shared "any stateless snapshot" protocol for that reason. A real
  nominal struct can, for free, once declared.
- **`Core` is always internal — the struct itself and every mapped field —
  regardless of the attached type's own access level, and never
  `@Flowable`** (verbatim-copied fields keep `private` if the host declared
  it; `public` is erased). It's a testing/preview seam, not part of the
  attached type's public API even when that type itself is `public` —
  consumers of a public host never need the twin, only the module's own
  tests do (same module, or a `@testable import`). No hand-rolled init is
  needed either: Swift's own memberwise-init synthesis already reproduces
  every field-specific behavior `@Flowable` would — verified directly: a
  property-wrapper field with no `init(wrappedValue:)` (`@Binding`)
  synthesizes a parameter of the *wrapper's* type, one that does
  (`@QueryCore`, `@Bindable`) synthesizes a parameter of the *wrapped* type,
  and `@ViewBuilder` directly on a stored `let` synthesizes a
  builder-closure parameter for a value-typed field, exactly like
  `@Flowable`'s own hand-written logic. Copied members keep their original
  access modifiers verbatim (a `public var body` inside an internal `Core`
  just caps at internal — legal).
- **The mapped rows.** `@State`/`@AppStorage`/`@SceneStorage` → `@Binding
  var name: T` (their storage can't be redeclared as itself on a plain
  struct — all three share one case since all three share the same shape,
  verified directly against the real SwiftUI interface: `wrappedValue` is
  `{ get nonmutating set }` and `projectedValue` genuinely *is* `Binding<T>`
  for each). (`@Binding` needs no row of its own —
  its rule-3 verbatim copy already lands on this exact shape, and it's the
  mock vehicle itself: `Binding(get:set:)` in a test captures every write.)
  `@Query` → `@QueryCore var name: T`, this package's own drop-in stand-in
  (see the `OutFlow` section above — `someCore.name` reads the fetched value
  directly). Every mapped
  stand-in is fabricatable from plain code — `Binding` from `.constant`/a
  getter-setter pair, `@QueryCore` needs no fabrication at all
  (`Core(items: [item], …)` just works) — which is what makes direct `Core`
  construction work with zero live-view machinery; see `makeCore` in
  `ShellTests.swift`. The whitelist is exactly the wrappers where a
  substitution buys a REAL mock — `@FocusState`/`@AccessibilityFocusState`
  were once here and got cut: their `.Binding` projections have no public
  initializer (verified directly — a test can't back one with its own
  closures) and their writes no-op outside a live view anyway (verified
  directly), a pass-through pretending to be a mock; as verbatim copies they
  behave identically when hosted.
- **The mapped source-of-truth wrappers must be private — enforced with a
  diagnostic, not accommodated.** `sourceOfTruthMustBePrivate`
  (`StoredProperty.swift`, checked in `collectStoredProperties`) rejects
  `@State`/`@AppStorage`/`@SceneStorage`/`@Query` declared non-private: they're a view's
  own source of truth, never something a caller supplies (`@Binding` is for
  that). Every renderer downstream can assume the substituted set is always
  private, with no "what if it's also public" case to reason about or test.
  Unknown wrappers carry no privacy rule — copied verbatim either way; a
  non-private one stays a memberwise-init parameter like any other
  non-private field.
- **The unknown rule: copy the whole declaration verbatim** — attribute text
  with any arguments (`StoredProperty.attributeText`), access modifier, and
  default value, spliced as-is by `renderShell`'s fallthrough. Whatever
  behavior lives in the attribute's own arguments (a
  `@GestureState(reset:)` closure, an `@Environment` key path, a
  `@ScaledMetric(relativeTo:)`) rides along byte-for-byte with nothing to
  reconstruct — proved live by `TrickyDragCardUITests`: an earlier design
  *reconstructed* `@GestureState var name: T` from just the bare wrapper
  name and silently dropped a custom reset closure for the default one; a
  later one wrapped the host's *live instance* in a dedicated
  `GestureStateCore` stand-in to carry it at runtime; the verbatim copy gets
  the same fidelity with no machinery, since `Core`'s field *is* the same
  declaration. A private copy is self-initializing by construction (the
  host compiled without an init assigning it) and so drops out of `Core`'s
  synthesized memberwise init — verified directly for all three
  self-initialization forms: attribute arguments (`@Environment(\.x)`),
  inline default (`@GestureState … = .zero`), and wrapper `init()`
  (`@Namespace`) — and it's
  unreadable from outside `Core` — sealed, the values just
  behave (`@Environment` reads the real environment reactively
  when `Core` is hosted — mock it there via `.environment(...)`, its own
  native story — and the default `EnvironmentValues` outside a live view;
  `@GestureState` starts a fresh gesture at its declared default). A
  *non-private* copy stays a memberwise parameter of the wrapper's own
  type.
- **`@ViewBuilder` rides along as init machinery — kept only
  for the stored-*closure* form.** For a stored closure
  (`let content: () -> Content`) the field type is already a closure, so the
  attribute is pure upside — real builder syntax (`if`/`for` inside the
  body) at `Core`'s own init call site. For a stored *value*
  (`let footer: Content`), keeping the attribute would make Swift's own
  synthesized init wrap the parameter in a builder closure purely to satisfy
  it (verified directly) — so it's dropped there entirely: `footer` stays a
  plain field, its synthesized init parameter just the bare value.
  `isFunctionType` is what tells the two forms apart, the same check
  `renderInFlowSplatFactory`'s `makeFlow(_:)` uses for its own reverse
  direction (which *does* still need the trivial-closure trick, since
  `@Flowable`'s init keeps `@ViewBuilder` on both forms). It's **not** a
  `@propertyWrapper` — a result-builder attribute, legal directly on stored
  properties (verified directly, `let` and `var` both).
- **Zero eligible fields still generates a (near-empty) `Core`** —
  `struct Core {}` — no diagnostic, mirroring `@Flowable`'s own graceful
  zero-property `init()` rather than `@Capability`'s "zero is an error"
  stance (Swift synthesizes the empty `init()` here on its own).
- **Automatic `View`/`ViewModifier` detection, off the attached type's own
  inheritance clause** (`detectHostKind`, in `ShellMacro.swift`): `struct
  Card: View` or `struct VM: ViewModifier` additionally declares `Core:
  View`/`: ViewModifier` — satisfied by the copied `body`/`body(content:)`.
  For `ViewModifier`, the copied `body(content:)`'s `Content` resolves to
  `Core`'s *own* `ViewModifier.Content` — a different concrete type from the
  host's (`typealias Content = _ViewModifier_Content<Self>`, keyed on the
  conforming type itself — verified directly against the real compiler),
  which is fine: each type satisfies the protocol independently.
  - **Syntax-only, not semantic — verified against the exact pinned dependency**:
    `DeclGroupSyntax` (what `ShellMacro.expansion` receives) exposes
    `inheritanceClause` directly, confirmed by reading the actual
    `.build/checkouts/swift-syntax` source at the resolved `603.0.2`. Detection
    reads that clause for a bare `View`/`ViewModifier` identifier — the same
    textual style `propertyWrapperName` already uses for property wrappers. It
    can't see conformance declared in a separate extension, via a typealias or
    protocol composition, or a qualified spelling (`SwiftUI.View`) — a macro
    never gets a type checker.
- See `Tests/CoreFlowTests/ShellTests.swift` for the model demonstrated
  end-to-end — fully-mocked direct `Core` construction (`makeCore`), the
  copied body/helper evaluating against mocked fields, and the `@MainActor`
  requirement on any test suite touching a `View`-conforming type (same
  reasoning as `OutFlow`'s equivalent note above) — and
  `Tests/CoreFlowTests/ShellSyntaxTests.swift` for the expansion shape,
  including the copy rules
  (`testHelpersStaticMembersAndNestedTypesAreCopiedButInitsAreNot`), the
  host-kind-detection cases, and the negative case (conformance in a
  separate extension isn't detected). Verified live by the ExampleApp's
  three views/UITests, all written in this model.

## @RawProperty — tricky points

Peer macro (`RawPropertyMacro.swift`) generating an internal `raw_name`
get/set accessor over a wrapped property's `_name` backing storage. Exists
because **the decision is HARD CODED in the compiler** — SE-0258: "always
named with a leading `_` and is always `private`", no spelling loosens it —
making the wrapper *instance* on a constructed value unswappable.
(https://github.com/swiftlang/swift-evolution/blob/main/proposals/0258-property-wrappers.md)
A standalone opt-in for hand-written code — `@Shell` no longer stamps it
anywhere (mocking happens at construction via hand-built
bindings); `QueryCoreTests`' `FakeCore` keeps it exercised. Type inference
is syntax-only: attribute generics verbatim (`@Binding<Bool>`), else the
annotation fills the generic, else a diagnostic; no wrapper attribute at
all is a diagnostic too. That `Wrapper<T>` spelling means it fits generic
wrappers only — bare `Namespace` can't be spelled from syntax.

## @Capability — tricky points

`member` macro that bundles every eligible *computed* property/method into a
`Capability` typealias + `capability` computed property. Entry point + collection +
rendering all live in `Sources/CoreFlowMacros/CapabilityMacro.swift` — doesn't
share `StoredProperty.swift`'s model at all (that's for *stored* properties; this
macro is deliberately about the opposite thing, and mixes properties with methods,
which `StoredProperty` has no concept of).

- **Works on an extension, unlike `@Flowable` — and that's not an oversight on
  its part.** `@Flowable` collects *stored* properties, and extensions can
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
  1-tuple collapse `@Flowable`'s `InFlowSplat` typealias does. **Zero** is a
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
`Sources/CoreFlowMacros/PickMacro.swift`, `KeyPathPick.swift`.

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

`Sources/CoreFlow/Reflector.swift`. Not a macro — a plain runtime `enum` with one
static generic function, `fieldNames<T>(of: T.Type) -> [String]`, kept in this
package because it's a small, natural companion to `@Flowable`'s generated members
rather than because it needs code generation of its own. No paired
`CoreFlowMacros` file, no `@attached`/`@freestanding` declaration — it's ordinary
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
- **Pairs with `@Flowable`** by pointing it at `InFlow`, not `InFlowSplat`:
  `Reflector.fieldNames(of: Point.InFlow.self)` reports real field names
  (`["x", "y"]`) because `InFlow` is labeled; the same call against
  `InFlowSplat` would report positional labels (`[".0", ".1"]`) instead, since
  `InFlowSplat` is deliberately unlabeled (see `@Flowable` above) — not a bug,
  just the wrong typealias for this use.
- **A top-level `private`/`fileprivate` type still restricts its own generated
  members' access to itself** — a `private struct Point` inside a test file means
  `@Flowable`'s generated `InFlow` is `private` too, which is scoped to
  `Point`'s own body/extensions, *not* file-wide like a top-level `private`
  declaration is. Reaching `Point.InFlow` from elsewhere in the same file
  needs `Point` to not be `private` (or the reference to live inside `Point`
  itself/an extension of it).

