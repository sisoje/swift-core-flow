# CLAUDE.md

A small, growing collection of independent Swift macros (plus `Reflector`, a small
non-macro addition that pairs with `@Flowable`), all in ONE package/target
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
| `ValueFlowMacros` | macro plugin | every macro's implementation, one `@main` `CompilerPlugin` listing all of them. One file per macro (`FlowableMacro.swift`, `ShellMacro.swift`, `CapabilityMacro.swift`, `PickMacro.swift`), plus shared stored-property collection + rendering (`StoredProperty.swift`, `MemberMacroEntry.swift`, `FieldRendering.swift`, `FlowableRendering.swift`) that `@Flowable` builds on and `@Shell` reuses (`ShellRendering.swift`), and TuplePicker's own parsing (`KeyPathPick.swift`, `TuplePickerSupport.swift`) |
| `ValueFlow` | library (the one product) | every macro's public attribute/expression declaration, one file per macro (`Flowable.swift`, `Shell.swift`, `Capability.swift`, `TuplePicker.swift`), plus three small non-macro additions: `Reflector.swift` (pairs with `@Flowable`, see below), and `QueryCore.swift`/`GestureStateCore.swift` (`@Query`/`@GestureState`'s drop-in stand-ins on `Core`/`OutFlow`, see the `@Flowable` OutFlow notes) |
| `ValueFlowTests` | test (XCTest + swift-testing, same target) | all coverage: `assertMacroExpansion` per macro, plus TuplePicker's and Reflector's real-compiled end-to-end suites |
| `Examples` | executable | combined playground for every macro (and Reflector) |

Adding a new macro: one new file in `ValueFlowMacros` for the implementation
(`Foo­Macro: MemberMacro`/`ExpressionMacro`), add it to `Plugin.swift`'s
`providingMacros`, one new file in `ValueFlow` for the public
`@attached`/`@freestanding` declaration pointing `#externalMacro(module:
"ValueFlowMacros", type: "FooMacro")`, a new `XCTestCase`/`@Suite` in
`ValueFlowTests`, and a `// MARK: -` section in `Examples/main.swift`. No new
Package.swift targets or products. If the macro generates something from a type's
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
Entry point: `Sources/ValueFlowMacros/FlowableMacro.swift`. Rendering: all six —
`renderFlowable` (the init), `renderInFlowSplatTypealias`,
`renderInFlowSplatFactory`, `renderInFlowTypealias`,
`renderInFlowProperty`, `renderOutFlowTypealias`, and `renderOutFlowProperty` — live in
`Sources/ValueFlowMacros/FlowableRendering.swift`; the last five are called
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
- **`private` means private, and it must mean something — enforced with two
  dedicated diagnostics, not silent exclusion.** A private property with no
  recognized wrapper at all (`private var cache = 0`) used to be silently
  excluded from the init/typealiases, with nothing to show for it in
  `OutFlow`/`Core` either — now it's `plainPrivatePropertyNotAllowed`:
  pure data flow has no room for opaque private state that's neither a source
  of truth nor something a caller supplies. And `@Binding`/`@Bindable`/
  `@ViewBuilder` — the wrapper kinds a *caller* supplies through the generated
  init — are the opposite of source-of-truth state, so declaring one private
  makes it unreachable; that's `callerSuppliedWrapperMustNotBePrivate`
  (`property.isCallerSuppliedWrapper`, `StoredProperty.swift`), a clearer,
  dedicated message rather than the generic "wrapper this macro doesn't
  recognize" one — these three ARE recognized, just never allowed private.
  Every *other* private property still needs a recognized source-of-truth
  wrapper (`@State`/`@Environment`/`@Query`/`@AppStorage`/`@SceneStorage`/
  `@FocusState`/`@Namespace`/`@GestureState`/`@AccessibilityFocusState`/
  `@ScaledMetric`) to be legal at all — that's the pre-existing
  `sourceOfTruthMustBePrivate`/`unsupportedPrivateWrapper` pair, now narrowed
  to fire only once the two checks above have ruled out the caller-supplied and
  no-wrapper cases. `private(set)`/`fileprivate(set)` fall into these same
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
`Sources/ValueFlow/Flowable.swift`.

`OutFlow`/`outFlow` — a labeled tuple typealias + computed property (`outFlowFieldType`,
`outFlowFieldReadExpression`, `renderOutFlowTypealias`, `renderOutFlowProperty`, all
in `FlowableRendering.swift`) wider than `InFlow`/`inFlow`, for
"give me a view's full externally-relevant *capturable* state, not just its
constructor data":

**Why this exists — testability, not just wider read access.** Any SwiftUI node
that owns or reads live state via
`@State`/`@Query`/`@AppStorage`/`@SceneStorage`/`@FocusState` introduces a
source of truth (SOT) that only works inside a real render pipeline (view
identity, a live `ModelContext`) — which makes it hard to test directly.
`OutFlow` converts that SOT into a plain, stateless snapshot: construct the
type, read `.outFlow`, assert on the fields — no live view hierarchy required.
That's the actual motivating idea behind targeting exactly these wrapper kinds,
not "read private state too" for its own sake. See
`Tests/ValueFlowTests/OutFlowTests.swift` for this property demonstrated
directly (`outFlowReadsFlowableFieldsAndRecognizedPrivateWrappersTogether`
constructs a `Card` and reads `.outFlow.isExpanded`/`.isOn` with no live view
ever installed).

**No recognized wrapper is excluded — `@Environment`/`@Namespace` included.**
An earlier revision left `@Environment` out of `OutFlow` on the theory that a
captured snapshot goes stale the instant the real environment changes, and
that its own mocking story (inject a different value where the type is
constructed/hosted) already covers testing it without this package's help.
That reasoning was reconsidered and reverted: every private property this
package recognizes at all *is* a source of truth, full stop, and
`@Shell` never excluded `@Environment` either — the asymmetry between
the two was itself the defect, not a deliberate design choice worth keeping.
`OutFlow`'s field set is now identical to `@Shell`'s.

- **Field set: `InFlow`'s fields, plus every recognized private
  source-of-truth wrapper** — `outFlowProperties(_:)` computes this as
  `properties.filter { !$0.isPrivate || $0.isQuery || $0.isBindingBackedStorage
  || $0.isFocusState || $0.isEnvironment || $0.isNamespace }`. There's no
  "unrecognized private state stays excluded" case left to filter here at
  all — a private property with no recognized wrapper (`private var cache =
  0`) or with some *other* wrapper this package hasn't been taught about
  (`@StateObject`, …) is refused outright by `collectStoredProperties`
  (`plainPrivatePropertyNotAllowed`/`unsupportedPrivateWrapper`,
  `StoredProperty.swift`) before it ever reaches this filter — every property
  `outFlowProperties` sees is already guaranteed legal.
- **Declaration order, preserved as one interleaved list** — not data-layout fields
  first with wrapper fields appended after. `outFlowProperties` filters
  `properties` (already declaration-ordered) in place, so a `@Query` field declared
  before a plain `public let` one comes first in `OutFlow` too.
- **The type mappings, all in `outFlowFieldType`**:
  - `@Query` (`isQuery`) → **always** `QueryCore<WrappedType>` — this
    package's own drop-in stand-in for the live wrapper
    (`Sources/ValueFlow/QueryCore.swift`, a plain non-macro `@propertyWrapper`
    like `Reflector` is a plain non-macro utility), **not** a passthrough of
    the declared type. One-to-one with the real `Query<Element, Result>`'s
    instance surface — verified directly against the `_SwiftData_SwiftUI`
    interface: exactly `wrappedValue`, `fetchError`, and `modelContext`, and
    **no `projectedValue`**, so `QueryCore` carries the same three members and
    no `$x` projection either. Reading `modelContext` outside a live container
    works — verified directly in the Examples playground, no crash — so the
    eager capture is safe even for snapshots built in plain code. An earlier
    revision synthesized a bare `(wrappedValue:, fetchError:)` tuple via
    `#pick` instead (and one before that dropped `modelContext` as
    unexercised plumbing); replaced by the real wrapper so `Core`'s field
    reads the fetched value directly — `core.items`, not
    `.items.wrappedValue` — making body code written against the live
    `@Query` property move onto `Core` unchanged. `QueryCore`'s init
    deliberately has no defaults: an init callable with `wrappedValue` alone
    would make Swift's synthesized memberwise init take the bare value and
    drop `fetchError`/`modelContext`; with all three required it takes the
    wrapper type itself, the same mechanism `@Binding` fields rely on.
  - `@GestureState` (`isGestureState`) → `GestureStateCore<WrappedType>` —
    the same drop-in move (`Sources/ValueFlow/GestureStateCore.swift`),
    wrapping the captured live wrapper *instance* whole
    (`GestureStateCore($x)`) and forwarding its exact surface — verified
    directly against the SwiftUI interface: `GestureState<Value>` exposes
    exactly `wrappedValue` (get-only, the mid-gesture rendering input) and
    `projectedValue` (itself — the value `.updating(_:)` takes), nothing
    else. So `core.x` reads the in-flight value and `.updating($x)` in
    `Core`'s body wires the real gesture, byte-identical to the live
    property's wiring. Mockable by seeding:
    `GestureStateCore(GestureState(wrappedValue: mock))` reads back the mock
    outside a live view — verified directly (a never-installed
    `GestureState` returns its seed) — so a test/preview renders `Core` as
    if mid-gesture.
  - `@State`/`@AppStorage`/`@SceneStorage` (`isBindingBackedStorage`) →
    `Binding<WrappedType>`, since these are the view's own externally
    read-*and-write*-able storage — all three wrappers' own `projectedValue`
    genuinely *is* `Binding<T>` (verified directly against the real SwiftUI
    interface, `@SceneStorage` included — `wrappedValue` is `{ get nonmutating
    set }`, same shape as `@State`/`@AppStorage`, no separate case needed).
  - `@FocusState` (`isFocusState`) → `FocusState<WrappedType>.Binding`, **not**
    `Binding<WrappedType>`, even though it's read via the same `$x`
    shortcut as the row above. Verified directly against the real SwiftUI
    interface: `FocusState<T>.Binding` (its own `projectedValue` type) exposes
    only `wrappedValue`, no public initializer at all and no conversion to
    `Binding<T>` — a hand-built `Binding(get:set:)` stand-in was considered and
    rejected, since it would satisfy neither `.focused(_:)` (which specifically
    wants `FocusState<T>.Binding`) nor anything else expecting the real
    projection back.
  - `@AccessibilityFocusState` (`isAccessibilityFocusState`) → an exact
    `@FocusState` clone — verified directly against the real SwiftUI
    interface: same nested `@propertyWrapper` `Binding` shape, settable
    `wrappedValue`, no conversion to `Binding<T>` — so it gets the identical
    treatment (`AccessibilityFocusState<T>.Binding`, read `$x`), and `snap.$x`
    feeds `.accessibilityFocused(_:)` directly.
  - `@ScaledMetric` (`isScaledMetric`) → the bare declared type, read `x` —
    get-only `wrappedValue`, **no `projectedValue` at all** (verified
    directly), same plain-capture rule `@Environment`/`@Namespace` follow.
    Deliberately never redeclared on `Core`: its `init(wrappedValue:)` takes
    the *base* value, but the host reads back the already-scaled one, so a
    redeclare would double-scale — and `relativeTo:` can't be carried over.
  - Everything else (non-private fields) uses `baseTypeText` unchanged — the same
    rule `InFlow` already applies.
- **Matching read-expression mappings, in `outFlowFieldReadExpression`**:
  `@Binding`/`@State`/`@AppStorage`/`@SceneStorage`/`@FocusState` all read the
  *projected* value, `$x` — one shared convention, no `@Binding`-only special
  case (verified directly: `Binding`'s own `projectedValue` is `{ self }`, so
  `$x` gives back the identical `Binding<T>` the backing storage `_x` would,
  write-through included — `_x` survives only on `fieldAssignment`'s side,
  where `$x` is immutable). For `@State`/`@AppStorage`/`@SceneStorage`/
  `@FocusState`, `$x` is **not** `_x`, which gives the wrapper instance itself
  (`State<T>`, not `Binding<T>`; verified directly) — only the resulting
  *type* differs across these four (see above); `@FocusState`'s own
  `projectedValue` happens to be `FocusState<T>.Binding` rather than
  `Binding<T>`, but it's reached the exact same way. `@Query` reads
  `QueryCore(wrappedValue: _x.wrappedValue, fetchError: _x.fetchError,
  modelContext: _x.modelContext)` — `_x` is the wrapper instance itself
  (`Query<Element, Result>`), the same underscore-prefixed access
  `@Binding`'s *assignment* side uses. Every other non-private field uses
  `fieldReadExpression` unchanged (`x`, or `$x` for `@Binding`).
- **Every recognized private source-of-truth wrapper needs an explicit type**
  — relaxes the general "private properties are exempt from needing a type"
  exemption specifically for these, in `collectStoredProperties`
  (`StoredProperty.swift`): `OutFlow` reads the type to build its field, so
  the exemption can't extend to any of them. `@Namespace` is the one
  exception — it needs *no* explicit type at all, since its wrapped type is
  always `Namespace.ID`; see its own note in `StoredProperty.swift`. The
  shared diagnostic message was reworded to say "initializer/stateless
  snapshot" to cover both reasons a type might be required.
- **Verified directly that a `@State`-derived `OutFlow` binding doesn't write
  through outside a live SwiftUI view render** — constructing a `@Flowable` type
  directly in plain code (never installed into a real view hierarchy) and mutating
  `outFlow.someStateField.wrappedValue` silently no-ops instead of persisting. This
  is `@State`'s own behavior (its storage only installs once SwiftUI actually
  renders the view), not a bug in `OutFlow` — a genuine caller-supplied `@Binding`
  field, by contrast, really does write through (it's just a getter/setter pair,
  not tied to view identity). `@SceneStorage`/`@FocusState` behave identically
  here — verified directly, same no-op-outside-a-live-view caveat, even though
  `@SceneStorage` is backed by persistent storage rather than in-memory view
  identity. See `OutFlowTests.swift`.
- **`@MainActor` is required on any test suite exercising `outFlow` on a
  `View`-conforming type** — verified directly (a real crash, not a guess): `View`
  conformance implicitly infers `@MainActor` isolation for the whole type, so
  touching its members from a nonisolated swift-testing `@Test` function crosses
  that isolation boundary at runtime and traps (`SIGTRAP`) under Swift 6 strict
  concurrency, even though it merely reads a computed property. A plain top-level
  script (`Examples/main.swift`) doesn't hit this — top-level code in a `main.swift`
  already runs on the main actor.

## NOT SUPPORTED: `@StateObject` / `@ObservedObject`

Neither wrapper is recognized by `@Flowable`/`@Shell`, on purpose,
not as a gap to fill in later. Both are Combine-era `ObservableObject`
wrappers — MVVM/ViewModel-shaped state, exactly what this package's
`@Flowable` (plain, `Equatable`-friendly data) and `@Shell`
(deterministic snapshots of SwiftUI's own native property wrappers) exist to
avoid. Declaring either one `private` — their normal form — is a compile
error (`unsupportedPrivateWrapper`, see `@Flowable — tricky points` above),
same as any other unrecognized private wrapper. See the
`swiftui-mv-architecture` skill for the broader argument against
`ObservableObject`/ViewModel patterns in SwiftUI generally.

## @Shell — tricky points

A separate `member` macro from `@Flowable` — not a mode of it, doesn't replace
`OutFlow`/`outFlow`, can be attached with or without `@Flowable` also present
(it collects the type's stored properties itself via the same shared
`validatedProperties`). Entry point: `Sources/ValueFlowMacros/ShellMacro.swift`.
Rendering: `renderShell`, in `Sources/ValueFlowMacros/ShellRendering.swift`.

Generates a nested `Core` struct — always internal, carrying no
`@Flowable` — plus a `core` computed property building one from the
current instance. Its field set is *identical* to `OutFlow`'s — `renderShell`
calls `outFlowProperties` directly rather than duplicating the filter (see
`FlowableRendering.swift`): every non-private participating property, plus
every recognized private source-of-truth wrapper —
`@Environment`/`@Query`/`@State`/`@AppStorage`/`@SceneStorage`/`@FocusState`/
`@GestureState`/`@AccessibilityFocusState`/`@ScaledMetric`/`@Namespace` — each captured once as a plain value.

- **Why a second, nominal member alongside `OutFlow`'s tuple at all**: tuples
  can't conform to protocols — verified directly, `type '(x: Int, y: String)'
  cannot conform to 'Equatable' — only concrete types such as structs, enums and
  classes can conform to protocols`. `OutFlow` can never support `Equatable`/
  `Codable`/a shared "any stateless snapshot" protocol for that reason. A real
  nominal struct can, for free, once declared.
- **`Core` is always internal — the struct itself, every field, and
  `core`'s own access — regardless of the attached type's own access
  level, and never `@Flowable`.** This is a purely internal testing/snapshot
  seam (`.core` for assertions, plus a `Core`-hosted `body`/
  `body(content:)` implementation), not part of the attached type's public API
  even when that type itself is `public` — consumers of a public host never need
  the snapshot, only the package's own tests do (from the same module, or a
  `@testable import`). No hand-rolled init is needed either: Swift's own
  memberwise-init synthesis already reproduces every field-specific behavior
  `@Flowable` would — verified directly: a property-wrapper field with no
  `init(wrappedValue:)` (`@Binding`) synthesizes a parameter of the *wrapper's*
  type, one that does (`@Bindable`) synthesizes a parameter of the *wrapped*
  type, and `@ViewBuilder` directly on a stored `let` synthesizes a
  builder-closure parameter for a value-typed field, exactly like
  `@Flowable`'s own hand-written logic. Because `Core`'s own type is
  always internal, `core`'s access is forced internal too — Swift
  rejects a more-accessible property with a less-accessible type (verified
  directly: "property must be declared internal because its type uses an
  internal type"). `body`/`body(content:)` on the *attached* type, by contrast,
  still mirrors that type's own access (`public` included) — verified directly
  that this compiles even though it reads `core` (internal) and
  returns it: `some View`'s opaque return type only exposes the `View`
  conformance, never the concrete `Core` type, so a `public` `body` can
  freely return an internal concrete value.
- **Every source-of-truth wrapper becomes a constructed value with a
  substituted attribute — or a plain `let` where no substitution exists.**
  `@Query` → `@QueryCore var name: T`, this package's own drop-in stand-in
  (see the `OutFlow` section above — same wrapper, same capture, `core.name`
  reads the fetched value directly). `@GestureState` → `@GestureStateCore var
  name: T`, the same drop-in move wrapping the captured live instance whole:
  `core.name` reads the mid-gesture value, `$name` hands `.updating(_:)` the
  real `GestureState<T>` (its `projectedValue` is itself — verified directly),
  so gesture wiring in `Core`'s body is byte-identical to the live property's,
  and a seeded instance (`GestureStateCore(GestureState(wrappedValue: mock))`)
  mocks any mid-gesture value in a test/preview (a seeded `GestureState` reads
  back its seed outside a live view — verified directly).
  `@State`/`@AppStorage`/`@SceneStorage` →
  `@Binding var name: T` (substituted since their storage
  can't be redeclared as itself on a plain struct — all three share this one
  case since all three share the same shape, verified directly against the
  real SwiftUI interface: `wrappedValue` is `{ get nonmutating set }` and
  `projectedValue` genuinely *is* `Binding<T>` for each). `@FocusState` →
  `@FocusState<T>.Binding var name: T` — its own substituted attribute,
  distinct from `@Binding` above, since `@FocusState`'s own `projectedValue` is
  `FocusState<T>.Binding`, **not** `Binding<T>` (verified directly against the
  real SwiftUI interface: it exposes only `wrappedValue` and `projectedValue`
  — itself — no public initializer at all and no conversion to `Binding<T>`).
  The real `FocusState<T>.Binding` is itself `@propertyWrapper`-attributed
  (verified directly), so it redeclares the same way `@Binding` does, just
  spelling a different wrapper — `snap.name` reads the unwrapped value,
  `snap.$name` hands back a real `FocusState<T>.Binding` usable directly with
  `.focused(_:)`, no fabrication involved. `@Environment`/`@Namespace` → a
  plain `let name: T`, no attribute at all — not because the value doesn't
  change, but because the *attribute* can't be preserved: `@Environment`'s
  `wrappedValue` has no public setter (verified directly: `error: cannot
  assign to property: 'colorScheme' is a get-only property`), and the
  synthesized init always assigns `self.x = x`; a plain, unattributed `let`
  has no such restriction. Always `let` for `@Environment`/`@Namespace`, not
  mirroring the original's `let`/`var` (always `var`, every property wrapper
  requires it) — the captured copy is a one-time snapshot, immutable by
  design. `@Namespace` is grouped with `@Environment` here rather than getting
  its own case: same get-only `wrappedValue` problem (verified directly), and
  unlike the `@Binding`-substituted wrappers or `@FocusState` it has **no
  `projectedValue` at all** to fall back on, so a plain `let` is the only
  option.
- **`@State`/`@Environment`/`@Query`/`@AppStorage`/`@SceneStorage`/`@FocusState`/`@GestureState`/`@AccessibilityFocusState`/`@ScaledMetric`/
  `@Namespace` must be private — enforced with a diagnostic, not
  accommodated.** `sourceOfTruthMustBePrivate` (`StoredProperty.swift`, checked
  in `collectStoredProperties`) rejects any of these ten declared
  non-private: they're a view's own source of truth, never something a caller
  supplies (`@Binding` is for that). Every renderer downstream can assume all
  ten are always private with no "what if it's also public" case to reason
  about or test — an earlier revision's field-set filters (`!$0.isPrivate ||
  $0.isQuery || …`) technically already handled a hypothetical non-private
  case correctly, but there was no reason to leave that door open when it's
  simply invalid usage. A private property carrying any *other*, unrecognized
  wrapper attribute (`@StateObject`, `@GestureState`, a future SwiftUI
  wrapper, …) is refused outright by a separate diagnostic
  (`unsupportedPrivateWrapper`) rather than silently falling through as
  ordinary opaque private state — the exact failure mode `@FocusState` hit
  before it was added here: it compiled fine, it just quietly never appeared
  in `OutFlow`/`Core`.
- **The rule for every other field: mirror the original property's own
  attribute and declared type onto `Core`, but never its mutability.**
  `Core` is a deterministic snapshot, so a field gets `var` only where
  Swift's own property-wrapper rule forces it (a genuine `@propertyWrapper`
  type — `@Bindable`, or any other real wrapper — requires `var` storage;
  verified directly, `@Bindable let model: Settings` is a compile error:
  "property wrapper can only be applied to a 'var'"). Everything else is
  `let` regardless of what the original property was declared as: a plain
  `var subtitle: String?` becomes
  `let subtitle: String?` on `Core` — a captured value, not a
  re-tweakable one. `@ViewBuilder` carries across (see next bullet) with `let`
  intact — it's **not** a `@propertyWrapper`, it's a result-builder attribute,
  legal directly on a stored `let` (verified directly: `@ViewBuilder let vb: ()
  -> Text` compiles). `@Bindable` carries across with `var` intact and needs no
  special handling beyond the general "genuine wrapper keeps var" rule — no init
  logic here ever recognized `@Bindable` specially even on the *original* type
  (it just does `self.model = model`, legal since `@Bindable`'s wrappedValue is
  a plain get/set), so mirroring it onto `Core`'s copy works
  identically under Swift's own synthesized init, with no extra logic here.
- **A genuine `@Binding` field mirrors verbatim into the exact same `@Binding
  var name: T` form `@State`/`@AppStorage`/`@SceneStorage` are substituted into
  above** — it already *is* that declaration in the original source, so
  mirroring it lands on the same shape with no extra logic, and Swift's
  synthesized init picks up every case identically (verified directly).
- **`@ViewBuilder` mirroring is a real win here, unlike `OutFlow`'s tuple —
  but only for the stored-*closure* form.** `OutFlow`'s tuple has no parameter
  position for trailing-closure sugar to attach to, so it deliberately strips
  `@ViewBuilder` down to a bare type. `Core` mirrors `@ViewBuilder`
  for a stored closure (`let content: () -> Content`): the field type is
  already a closure, so the attribute is pure upside — real builder syntax
  (`if`/`for` inside the body) at its own init call site, not just
  documentation. For a stored *value* (`let footer: Content`), mirroring the
  attribute would make Swift's own synthesized init wrap the parameter in a
  builder closure purely to satisfy it (verified directly) — overhead with no
  benefit for a value that's already built and just being copied through — so
  it's dropped there entirely: `footer` stays a plain `let footer: Content`,
  and constructing `Core` in the `core` computed property
  passes it straight through (`footer: footer`), no wrapping needed on either
  side. `isFunctionType` is what tells the two forms apart, the same check
  `renderInFlowSplatFactory`'s `makeFlow(_:)` uses for its own reverse
  direction (which *does* still need the trivial-closure trick, since
  `@Flowable`'s init keeps `@ViewBuilder` on both forms).
- **Zero eligible fields still generates a (near-empty) `Core`** —
  `struct Core {}` plus `var core: Core {
  Core() }` — no diagnostic, mirroring `@Flowable`'s own graceful
  zero-property `init()` rather than `@Capability`'s "zero is an error" stance;
  an empty core snapshot is a sensible, if trivial, concept (Swift
  synthesizes the empty `init()` here on its own, same result).
- **Automatic `View`/`ViewModifier` detection, off the attached type's own
  inheritance clause** (`detectHostKind`, in `ShellMacro.swift`): `struct
  Card: View` or `struct VM: ViewModifier` gets two members beyond the usual
  pair — `Core` is additionally declared `: View`/`: ViewModifier` (a
  requirement only; the real `body`/`body(content:)` is still hand-written, in a
  separate extension of `Core`), and the attached type gets the mechanical
  delegation for free: `var body: some View { core }`, or `func
  body(content: Content) -> some View { content.modifier(core) }`.
  - **Discoverability of the hand-written half is a doc comment, not a
    diagnostic** — a `///` comment generated directly on the `Core` struct
    declaration (only when `hostKind != .none`) states exactly what to write
    and where, visible via Quick Help/jump-to-definition. Deliberately not a
    compiler diagnostic: the macro has no semantic model, so it can never know
    whether the implementing extension already exists elsewhere in the module
    — a `.note`/`.warning` would either nag permanently (never clears once
    implemented) or not fire at all. A doc comment has no such cost; Swift's
    own "does not conform to protocol" build error already enforces that the
    extension gets written at all, this only clarifies *what* to write, since
    that error alone doesn't say "extend `Core`, not the outer type."
  - **Syntax-only, not semantic — verified against the exact pinned dependency**:
    `DeclGroupSyntax` (what `ShellMacro.expansion` receives) exposes
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
    the *conforming type itself* — `VM.Content` and `VM.Core.Content` are
    different concrete types no constraint can unify (`error: arguments to
    generic parameter 'Modifier' ('VM' and 'VM.Core') are expected to be
    equal`, reproduced directly against the real compiler both as a minimal
    repro and against this exact generated code). `.modifier(_:)` only needs its
    argument to conform to `ViewModifier`, not to share a `Content` — sidesteps
    the whole problem.
- See `Tests/ValueFlowTests/ShellTests.swift` for this demonstrated
  end-to-end (including the `@MainActor` requirement on any test suite
  exercising `core` on a `View`-conforming type — same reasoning as
  `OutFlow`'s equivalent note above) and
  `Tests/ValueFlowTests/ShellSyntaxTests.swift` for the expansion shape,
  including the host-kind-detection cases and the negative case (conformance in
  a separate extension isn't detected).

## @Capability — tricky points

`member` macro that bundles every eligible *computed* property/method into a
`Capability` typealias + `capability` computed property. Entry point + collection +
rendering all live in `Sources/ValueFlowMacros/CapabilityMacro.swift` — doesn't
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
package because it's a small, natural companion to `@Flowable`'s generated members
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

