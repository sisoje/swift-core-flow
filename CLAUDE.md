# CLAUDE.md

A small, growing collection of independent Swift macros (plus `Reflector`, a small
non-macro addition that pairs with `@Flowable`), all in ONE package/target
pair — not one target per macro. Consumers add a single dependency
(`.product(name: "CoreFlow", package: "CoreFlow")`) and get every macro; adding a
new macro is "add a file to each of two targets," not "add a product + three targets
to Package.swift." (Per-macro target/product sets were considered and rejected:
the ceremony-per-macro isn't worth dependency granularity nobody needs.)

- Build/test: `swift build && swift test`
- Format: `swift format --in-place --recursive Sources Tests`
- Docs: `README.md` — per-macro reference. The conceptual article ("SwiftUI
  Data Flow Masterclass": nodes, waves, boundary events, the shell/core
  split, execution-log testing — taught macro-free as a manual two-view
  split) is published on Medium, linked from the README's intro; the macros
  mechanize the same split, one conceptual story with different vehicles.
  House prose rules: facts
  and decisions, never removal history; compressed, no information lost;
  references at the bottom; nothing named before its chapter introduces it.
- Example app (`CoreFlowExample`, xcodegen; the directory holds exactly
  `project.yml`, `test.sh`, `generate.sh`, and `SPEC.md` — the Swift
  sources are deliberately collapsed into the spec and regenerate from it
  (`sh generate.sh`, headless claude);
  `project.yml`/`test.sh`/`generate.sh` are kept verbatim as part of the
  spec. Regenerate, then verify with `sh test.sh` in the directory — the
  UI tests component-test the generated `Core`s live.
  `-collect-test-diagnostics never` skips post-test simulator
  diagnostics, which intermittently time out at exactly 600s on this
  Xcode beta — observed once; the flag makes run time deterministic).
  The production shape: `CoreFlowExampleUI` is a real SPM library holding
  ALL the components, one file each (host, scenario, `#Preview`) — the
  reading-list set (internal `@Shell` hosts with SwiftData
  `@Query` + `@AppStorage`, their composed public `@Flowable @Shell`
  `ReadingListScreen` — the app's one entry point — and a
  `BookStore` capability: a struct of closures behind a public `@Entry`,
  mocked by construction, always-equal `Equatable`) and five internal
  tricky-wrapper components (plain `@GestureState`,
  `@GestureState(reset:)`, `@FocusState`, a `ViewModifier` host, an
  async throwing action). `RealApp` (scheme `CoreFlowRealApp`) consumes the
  composed screen with a plain import and live wrappers, and owns the live
  side of the capability — a `ViewModifier` injector reading the real
  `modelContext`; `TestApp` (scheme
  `CoreFlowTestApp`, one file) reaches the internal scenarios via
  `@testable import`, selected via the `SCENARIO` env var
  (`defaultScenario` when unset, so Cmd-R just works).
  Every scenario hosts a CORE — often bare `Core()`, since the substituted
  `@TestState` fields own and log their own state; the scenario adds only
  what the host takes from callers (`@TestAction` closures, data
  arguments, `@Binding` backings). The app installs the one sink on the
  root view via `.testLog { … }`, appending `(name, value)` into
  plain `@State` the moment it happens — at the write site, not via a
  view-layer observer replaying history. That log is exposed on the
  scenario `Group`'s own accessibility channels
  (`.accessibilityElement(children: .contain)` + identifier `log`, names
  JSON in `label`, values JSON in `value` — no phantom view, no opacity
  tricks, and JSON survives any description content; XCUITest reads
  `.label`/`.value`). Tests wait on their own UI finish signal —
  `log.wait(for: \.label, toEqual:)` against the expected names JSON, which
  doubles as the names assertion (names are fixed identifiers, raw-string
  comparable) — then `XCTAssertEqual` on `app.logValues` decoded as
  `[String]`. In-process assertion is deliberate — no recorded snapshot
  file: the element carries the same data live, with no record/re-record
  dance and no unstable-description poisoning of an all-or-nothing file
  diff. Value-streaming scenarios (drag distances) stay
  predicate-asserted.

Targets Swift 6.3 (`swift-tools-version: 6.3`); swift-syntax `600.0.0..<700.0.0`, whose
APIs are stable across the whole Swift 6.x line. Swift 6 language mode (strict
concurrency) throughout.

## Package layout

| Target | Kind | Contents |
|---|---|---|
| `CoreFlowMacros` | macro plugin | every macro's implementation, one `@main` `CompilerPlugin` listing all of them. One file per macro (`FlowableMacro.swift`, `ShellMacro.swift`, `CapabilityMacro.swift`, `PickMacro.swift`, `TestSupportMacros.swift` — that one holds `@TestState` + `@TestAction` — `TestFocusStateMacro.swift`, and `UnstructuredTaskMacro.swift`), plus shared stored-property collection + rendering (`StoredProperty.swift`, `MemberMacroEntry.swift`, `FieldRendering.swift`, `FlowableRendering.swift`) that `@Flowable` builds on and `@Shell` reuses (`ShellRendering.swift`), and TuplePicker's own parsing (`KeyPathPick.swift`, `TuplePickerSupport.swift`) |
| `CoreFlow` | library (the one product) | every macro's public attribute/expression declaration, one file per macro (`Flowable.swift`, `Shell.swift`, `Capability.swift`, `TuplePicker.swift`, `TestSupport.swift` — `@TestState`/`@TestAction`, `testLog`, `TestLog` — `TestFocusState.swift`, and `UnstructuredTask.swift` — `@UnstructuredTask` plus its runtime `TaskStorage`/`CancellableTask`), plus two small non-macro additions: `Reflector.swift` (pairs with `@Flowable`, see below) and `QueryCore.swift` (`@Query`'s drop-in stand-in on `Core`, see the `@Shell` notes) |
| `CoreFlowTests` | test (XCTest + swift-testing, same target) | all coverage: `assertMacroExpansion` per macro, plus real-compiled end-to-end suites (TuplePicker, Reflector, Shell's `Core`, `QueryCore`, the test-support macros) |

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

`StoredProperty` carries two separate channels, deliberately never mixed:
the parsed fields (`name`, `type`, `defaultValue`, `wrapperName`, `isLet`,
`isPrivate`) are `@Flowable`'s init/typealias channel and the substituted
rows'; the raw nodes (`varDecl`, `binding`) are `@Shell`'s verbatim-copy
channel — copies re-render the host's own syntax and never reassemble a
declaration from parsed pieces.

Two macro-boundary decisions worth knowing if you're extending it further:

- **Everything a `@Flowable` type gets comes from the one attribute** — there
  is deliberately no separate macro for the tuple typealias, and no init
  taking the whole tuple as a single parameter (`InFlowSplat` is declared,
  nothing consumes it as one init argument). If a future macro wants a
  tuple-parameter init, `renderInFlowSplatTypealias` in
  `FlowableRendering.swift` already has the tuple-vs-bare-type collapse logic
  to build on.
- **A macro that combines what two existing macros generate should collect
  stored properties ONCE and call each renderer directly** — not be spelled as
  "stack the two existing attribute macros" on the same type. Stacking works
  when the generated member sets don't collide, but it collects (and
  diagnoses) the same properties once per stacked macro.

## @Flowable — tricky points

`member` macro that writes a memberwise `init` at the type's own access
level, for a struct, class, or actor — plus two tuple typealiases: an
unlabeled `InFlowSplat` with a `makeFlow(_:)` factory building `Self` *from*
one (splat-friendly construction), and `InFlow`, its labeled twin
(readable, `Mirror`-reflectable). Entry point:
`Sources/CoreFlowMacros/FlowableMacro.swift`. Rendering: all four —
`renderFlowable` (the init), `renderInFlowSplatTypealias`,
`renderInFlowSplatFactory`, and `renderInFlowTypealias` — live in
`Sources/CoreFlowMacros/FlowableRendering.swift`; the last three are called
from inside the first, so one expansion always produces all four together
(or just the bare init, with zero properties to alias/build from).

The init:
- **Syntax-only, no real type inference — except three unambiguous literal
  kinds.** A property that becomes a parameter needs an explicit type — *unless*
  its inline default is a bare `Bool`/`Int`/`String` literal (`var isOn = false`,
  `var count = 0`, `var label = "x"`), inferred straight off the literal's own
  syntax node kind (`inferredLiteralType`, `StoredProperty.swift`) with no type
  checker involved — same spirit as `@Namespace`'s auto-inferred `Namespace.ID`
  just below. Anything else uninferable (a call, an identifier, `nil`, a
  collection literal, …) still needs an explicit annotation. Note an
  inline-initialized instance `let` with one of these three literal defaults
  (`let seed = 42`) gets *past* the missing-type check and fails on
  Swift's own `let`-reassignment error instead — see "No stored `let`
  constants" below; either way it won't compile, only where the failure
  surfaces differs.
- **`private` marks a source of truth — nothing else; enforced with
  dedicated diagnostics, not silent exclusion.** Data flows in through
  non-private properties; state lives in private wrapped ones. A private
  property with no wrapper at all (`private var cache = 0`) is refused
  (`plainPrivatePropertyNotAllowed`): opaque state that neither flows in
  nor is runtime-managed sits outside the data flow entirely. And `@Binding`/
  `@ViewBuilder` — the kinds a *caller* supplies through the generated
  init — are the opposite of source-of-truth state, so declaring one private
  makes it unreachable; that's `callerSuppliedWrapperMustNotBePrivate`
  (`property.isCallerSuppliedWrapper`, `StoredProperty.swift`). Any *other*
  private property just needs *some* wrapper: the mapped source-of-truth set
  (`@State`/`@FocusState`/`@AppStorage`/`@SceneStorage`/`@Query`,
  `sourceOfTruthMustBePrivate`'s
  domain — those must be private) or any unmapped wrapper (`@Environment`,
  `@GestureState`, `@StateObject`, a custom one, …), which
  carries no privacy rule at all — `@Shell`'s verbatim-copy default means
  unrecognized wrappers need no gatekeeping.
  `private(set)`/`fileprivate(set)` fall into these same
  diagnostics (the `isPrivate` check matches the keyword regardless of the
  `(set)` detail) — deliberately not special-cased: setter-restricted
  properties have no place in pure data flow either.
- **`@Binding` is the kept exception:** threaded as a projected `Binding<T>`, assigned
  `self._x = x`.
- **`@ViewBuilder` has two forms, and must be a `let`.** Stored closure
  `let vb: () -> Content` → `@ViewBuilder vb: @escaping () -> Content`,
  `self.vb = vb`. Stored value `let vb2: Content` → `@ViewBuilder vb2: ()
  -> Content`, `self.vb2 = vb2()` — the init *calls* the builder. A
  `@ViewBuilder var` is refused (`viewBuilderMustBeLet`, shared
  collection, so it fires under `@Shell` too): builder content is
  caller-supplied through the generated init and never reassigned.
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

The `InFlow` typealias — `InFlowSplat`, labeled, same collapse/zero rules
and same `wrapViewBuilder: false`:
- **Exists for readable spelling and real `Mirror` support.** Verified
  directly: `Mirror(reflecting:)` reports each field's actual name over a
  *labeled* tuple, only positional labels (`.0`, `.1`) over an *unlabeled*
  one — `InFlowSplat` alone can't support generic field reflection (see
  `Reflector` below), `InFlow` can.
- **Feeds `makeFlow(_:)` with no conversion** — an `InFlow` value converts
  into the unlabeled parameter like any differently-labeled tuple (see "Why
  unlabeled" above).

Deliberately NOT generated: an accessor reading an instance back out into an
`InFlow` (data flows in at construction; nothing needed the backward
read), a field-names member (`Reflector.fieldNames(of:
SomeType.InFlow.self)` already reports any generated tuple's field names),
and any state-snapshot member wider than `InFlow`
(a tuple over private wrapper state can't conform to protocols or host
live; `@Shell`'s `Core` is the one snapshot story, over this same field
set — see below).

`QueryCore` (`Sources/CoreFlow/QueryCore.swift`, a plain non-macro
`@propertyWrapper` the way `Reflector` is a plain non-macro utility) — the
drop-in stand-in `@Shell` substitutes for `@Query` (`@QueryCore var name:
T`). One-to-one with the real `Query<Element, Result>`'s instance surface —
verified directly against the `_SwiftData_SwiftUI` interface: exactly
`wrappedValue`, `fetchError`, and `modelContext`, and **no
`projectedValue`**, so `QueryCore` carries the same three members (its
`modelContext` private) and no
`$x` projection either — a bare `(wrappedValue:, fetchError:)` tuple is
deliberately not enough. The point is read-surface parity with the live
wrapper: the host's `body` text (`items.isEmpty`, `ForEach(items)`) is
copied onto `Core` verbatim, and it compiles there only because
`core.items` still reads the array directly — a tuple field would force
`.items.wrappedValue` on every copied read. `modelContext` is
environment-fed like the live wrapper's — a private `@Environment`
(`\.modelContext`) field, installed when `Core` is hosted (`QueryCore` is
a `DynamicProperty`; mock via `.modelContainer`/`.environment`), never
read unhosted, not an init parameter. `fetchError` defaults to `nil` — a
test mocking a
fetched result almost never cares: `QueryCore(wrappedValue:
[item])` just works. An init callable with `wrappedValue` alone makes
Swift's synthesized memberwise init for a `@QueryCore` field take the
*bare* value (verified directly, locked in by `QueryCoreTests`) —
deliberately so: tests write `Core(items: [item], title: "t")` with no
`QueryCore` spelling at all.

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

A separate `member` macro from `@Flowable` — not a mode of it, can be
attached with or without `@Flowable` also present
(it collects the type's stored properties itself via the same shared
`validatedProperties`). Entry point: `Sources/CoreFlowMacros/ShellMacro.swift`.
Rendering: `renderShell`, in `Sources/CoreFlowMacros/ShellRendering.swift`.

Generates a nested `Core` struct — always internal, carrying no
`@Flowable` — the host's standalone twin: the functional core to the
host's imperative shell (Bernhardt/Wlaschin/Seemann — links in README's
References; the masterclass teaches the same split by hand). Same logic,
every boundary observable — own state logged, external sources mocked as
data (which also severs their event channels: no storage change or fetch
notification can trigger a wave mid-test), effects as closures. Two
transform rules, in `renderShell`'s order:
**rule 1**, the substitution whitelist (`isSubstitutedOnCore`,
`StoredProperty.swift` — the only wrappers this macro really knows, all
required private): `@State`, the view's OWN state → `@TestState private`,
the host's line with just the wrapper token renamed — still private,
sealed out of the memberwise init, starting at the host's inline default,
logging every mutation. The initial value is part of the component's
definition, never a test parameter, so the default is required
(`stateNeedsInlineDefault`, checked in `ShellMacro` against the carried
`binding` node — `@Shell`'s own rule: `@Flowable` renders nothing from a
private `@State` and has no stake, locked by a `FlowableTests` case).
`@FocusState`, the view's own focus → `@TestFocusState private`, the same
rename treatment — no default to carry (`@FocusState` has no
`init(wrappedValue:)`, so a host line never has one; the substitute's
storage peer self-initializes).
`@AppStorage`/`@SceneStorage`, EXTERNAL storage → `@Binding var name: T` —
a dependency the constructor supplies; keys dropped, a test twin doesn't
persist. `@Query` → `@QueryCore var name: T` — the fetched result as an
init parameter, no SwiftData stack (see the `QueryCore` notes above);
**rule 2**, everything else, wrapper or not: the host's own declaration
node re-rendered as written — attribute arguments, `let`/`var`, default,
and any `willSet`/`didSet` observer block ride along byte-for-byte (the
`binding` is spliced whole). `public` is erased — Core is internal;
`private` stays — a private copy is
self-initializing and sealed out of the memberwise init, and erasing it
would resurface the field as a wrapper-typed init parameter. A plain
private field can't reach rendering (collection refused it —
`plainPrivatePropertyNotAllowed`), which rule 2 asserts; the `@State`
rename likewise asserts `isPrivate` (backed by `sourceOfTruthMustBePrivate`).
Asserts are internal tripwires for package developers only — the user-facing
contract is always a diagnostic at collection, never a macro crash.
Plus a verbatim copy
of every non-stored member (`copiedMemberSources`, `ShellMacro.swift`) —
`body`, helpers, methods, `static` members, nested types. Initializers are
the one member kind *not* copied: `Core` is constructed through Swift's
synthesized memberwise init, and a copied init would suppress it. No `core`
capture property off the live host either — Core is for
testing, tests construct it directly, and a unit test never has a live host
to capture from. The host runs its own hand-written body. Plain fields keep
the host's own `let`/`var` (a `let` with a default is a constant and drops
out of Core's memberwise init, exactly like on the host); private fields —
`@TestState` substitutions and verbatim copies alike — are sealed, they
just behave (and the `@TestState` ones log). Mocking
happens at construction — no post-construction instance swapping, no raw
backing accessors; where raw backing access is genuinely needed, a
same-file extension init/accessor
reaches `_name` by hand (see `QueryCoreTests`' `FakeCore`). Backing genuine
`@Binding` parameters and the external-storage substitutions is USE-SITE
code, deliberately not generated: a
test backs one with `.constant`, a `Binding(get:set:)` capturing writes
into a local, or a hand-written `@Observable @MainActor` model class whose
`Bindable(model).x` projection mints a real write-through binding in plain
code, no view needed (`handWrittenObservableModelBacksABinding` in
`ShellTests.swift` — note @Observable can't attach to a LOCAL type, so
such a model must be file-scoped). A generated binding-wiring model class
was considered and rejected — the few situational lines it would save
belong at the use site, shaped by the test. If anyone generates one
anyway, three verified facts:
the compiler expands attached macros inside another macro's generated
code just fine (`@TestState`/`@Binding`/`@QueryCore` today); `@MainActor`
must be explicit on a generated class because a nested type does NOT
inherit the enclosing View-conformance isolation (verified directly); and
a generated observable class must be a SIBLING of `Core`, not nested
inside it — nesting breaks `@Observable`'s extension-macro half, which
type-checks but fails at link with a missing `Observable` conformance
descriptor for the doubly-nested class (one level of macro-generated
nesting is the compiler's limit; both verified directly).

The copy is legal because it happens inside `@Shell`'s *own* expansion —
only *cross*-expansion name references are forbidden, the same Swift-level
rule that makes `#Preview` unable to see `Core` or any macro-generated name
(verified directly, five ways). `#Preview { Card() }` works since the
host's `body` is hand-written source, and a mocked `Core` previews through
any hand-written wrapper — the example app's scenarios double as exactly
that (`#Preview { DragCardScenario() }`): the scenario is an ordinary
name, so the cross-expansion rule never triggers. A macro-generated name
also fails in a file-scope TYPE position (`func f() -> DragCard.Core` →
"has no member 'Core'", verified directly) — reference it in expressions
or behind `some View`. It compiles on both types because every
field has read-surface parity — designed in for the mapped ones (`name`
reads the bare value on both sides; `$name` is `Binding<T>` on both, the
`@TestState` substitution generating its own private `$name`), trivially
true for a verbatim copy, because it *is* the same declaration. The
copied text is dedented first (`dedented`, `ShellMacro.swift`) — the
expansion machinery re-shifts every line by the splice position, so without
it copies land double-indented. Members in a separate extension of the host
aren't seen (same syntax-only limitation as host-kind detection).

- **Why a nominal struct, not a tuple**:
  tuples can't conform to protocols — verified directly, `type '(x: Int, y:
  String)' cannot conform to 'Equatable' — only concrete types such as
  structs, enums and classes can conform to protocols`. A tuple snapshot can
  never support `Equatable`/`Codable`/a shared "any stateless snapshot"
  protocol, carry copied members, or host live. A real nominal struct can,
  for free, once declared.
- **`Core` is always internal, regardless of the attached type's own access
  level, and never `@Flowable`.** Field access follows the rule: the
  `@State` substitution stays private (the view's own source of truth),
  the `@Binding`/`@QueryCore` substitutions are internal, verbatim copies
  keep their own access with `public` erased. It's a testing/preview
  seam, not part of the attached type's public API even when that type
  itself is `public` — consumers of a public host never need the twin,
  only the module's own tests do (same module, or a `@testable import`).
  No hand-rolled init is
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
- **The mapped rows, and what each substitution buys.** `@State` →
  `@TestState private`: the drop-in that keeps the field live while
  logging every mutation — ownership unchanged (an internal source of
  truth is never a caller's; moving it up would falsify the component's
  data flow just to observe it), the write site now emits evidence.
  Private + defaulted means excluded from the memberwise init entirely
  with the init staying internal (verified directly — `makeCore` in
  `ShellTests.swift` constructs without it). `@AppStorage`/`@SceneStorage`
  → `@Binding`: external storage is a dependency, and the binding is the
  mock vehicle — a test supplies the storage and captures every write.
  Legal because the shapes match (verified directly against the real
  SwiftUI interface: `wrappedValue` is `{ get nonmutating set }`,
  `projectedValue` genuinely *is* `Binding<T>`), and needed because a
  binding read off a directly-constructed instance of the real wrappers
  doesn't write through outside a live view render (verified directly for
  `@State` and `@SceneStorage` both), while a caller-supplied
  `Binding(get:set:)` writes through regardless — a getter/setter pair,
  not tied to view identity. (`@Binding` needs no row of its own — its
  verbatim copy already IS the mock vehicle.) `@Query` → `@QueryCore`:
  the fetched result as data — `Core(items: [item], …)` just works, and
  the live wrapper's change-notification channel is gone with it. Every
  mapped stand-in is fabricatable from plain code, which is what makes
  direct `Core` construction work with zero live-view machinery; see
  `makeCore` in `ShellTests.swift`. `@FocusState` → `@TestFocusState`:
  not a mock — none is possible (`FocusState<T>.Binding` is
  `@propertyWrapper` but has NO public initializer, and focus writes no-op
  outside a live view; both verified directly against the real interface) —
  but a live instrument: the substitute holds a REAL `FocusState` peer, so
  hosted behavior is unchanged and every programmatic write logs (see the
  `@TestFocusState` section below). `@AccessibilityFocusState` is
  deliberately NOT whitelisted — an exact `@FocusState` clone
  interface-wise, but no substitute macro exists for it yet, so it rides
  rule 2 verbatim.
- **The mapped source-of-truth wrappers must be private — enforced with a
  diagnostic, not accommodated.** `sourceOfTruthMustBePrivate`
  (`StoredProperty.swift`, checked in `collectStoredProperties`) rejects
  `@State`/`@FocusState`/`@AppStorage`/`@SceneStorage`/`@Query` declared non-private: they're a view's
  own source of truth, never something a caller supplies (`@Binding` is for
  that). Every renderer downstream can assume the substituted set is always
  private, with no "what if it's also public" case to reason about or test.
  Unknown wrappers carry no privacy rule — copied verbatim either way; a
  non-private one stays a memberwise-init parameter like any other
  non-private field.
- **Every property needs an explicit type or an inferable literal
  default**, enforced in `collectStoredProperties` (`StoredProperty.swift`):
  the substituted rows read `property.type` to declare their stand-in
  field (`@Binding var name: T`). Verbatim copies never reconstruct a
  type — a host line without an annotation (`var flavor = "mild"`,
  `@Namespace private var ns`) copies without one, and compiles on `Core`
  by the same inference/wrapper rules that compiled it on the host.
  `@Namespace` needs *no* annotation at all, since its wrapped type is
  always `Namespace.ID`; see its own note in `StoredProperty.swift`.
- **The verbatim rule: re-render the host's own node** — `p.varDecl` with
  the one `binding`, modifiers filtered, spliced by `renderShell`.
  Whatever behavior lives in the attribute's own arguments (a
  `@GestureState(reset:)` closure, an `@Environment` key path, a
  `@ScaledMetric(relativeTo:)`) rides along byte-for-byte with nothing to
  reconstruct — a rebuilt declaration would silently swap a custom
  `reset:` closure for the default one; the copy can't, since `Core`'s
  field *is* the same declaration. The same rule covers attribute
  spellings with no bare wrapper identifier to report
  (`@MyModule.Tracked`) — copied, not mistaken for plain fields. A
  private copy is self-initializing by construction (the
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
- **`@ViewBuilder` rides the verbatim rule like everything else, on BOTH
  its forms** — the stored closure keeps builder syntax at `Core`'s init
  call site, and the stored value keeps the attribute too, meaning
  `Core`'s synthesized init takes that parameter as a builder closure
  rather than a bare value (the synthesis fact above) — the host's own
  call shape, and matching it is the point of a verbatim copy. A
  `@ViewBuilder var` never reaches rendering (`viewBuilderMustBeLet`).
  It's **not** a `@propertyWrapper` — a result-builder attribute, legal
  directly on stored properties (verified directly).
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
    never gets a type checker. A qualified `@SwiftUI.State` is the same
    story on the wrapper side: no bare identifier to report, so it rides
    rule 2 as an unknown wrapper, consistently unrecognized everywhere.
- **`@MainActor` is required on any test suite touching a
  `View`-conforming type's members** — `Core` included. Verified directly
  (a real crash, not a guess): `View` conformance implicitly infers
  `@MainActor` isolation for the whole type, so a nonisolated swift-testing
  `@Test` function crosses that boundary at runtime and traps (`SIGTRAP`)
  under Swift 6 strict concurrency, even just reading a computed property.
- See `Tests/CoreFlowTests/ShellTests.swift` for the model demonstrated
  end-to-end — direct `Core` construction (`makeCore`), the
  external-storage binding capturing writes, and the `@MainActor`
  requirement above in force (body/heading stay unevaluated there: the
  copied `@Environment` would be an uninstalled read, a SwiftUI runtime
  issue) — and
  `Tests/CoreFlowTests/ShellSyntaxTests.swift` for the expansion shape,
  including the copy rules
  (`testHelpersStaticMembersAndNestedTypesAreCopiedButInitsAreNot`), the
  diagnostics, the host-kind-detection cases, and the negative case
  (conformance in a separate extension isn't detected). Verified live by
  the example app's scenarios/UITests, all written in this model
  (regenerable from its `SPEC.md`).

## @TestState / @TestAction — tricky points

Per-property mutation-logging macros with two jobs: hand-written test-host
views (scenarios), and `@Shell`'s own `@State` substitution on `Core`
(`TestSupportMacros.swift`; declarations plus `testLog`/`TestLog` in
`Sources/CoreFlow/TestSupport.swift`). The model is how you'd test
`Button`: the contract is "a tap calls the action", so mock the action
with a logger and assert it fired on a real tap. A `Core`'s whole behavior
is its boundary events — state writes and action calls — so scenarios
inject logging mocks (actions inert, `= { _ in }`) and tests assert the
ordered execution log, never an effect. No type-level macro — attach
`@TestState` to a stored `var` (ANY type, function types included: a `var`
closure means someone wants to mutate the closure itself, and its `$name`
binding is exactly that) and `@TestAction` to a stored `var` closure. Both
hardcode the seam — no key-path parameter. NO diagnostics: an unspellable shape (missing
type/default, `let` on either macro, non-closure on `@TestAction`)
generates nothing, and the use site fails in the compiler's own words
(`@Shell` diagnoses the missing-default case itself before it gets that
far — `stateNeedsInlineDefault`).
Per-property attachment is deliberate — no type-level `@TestHost(\.keyPath)`
macro deciding which properties participate; each property opts in where
it's declared.

- **`@TestState var count: Int = 0` is a drop-in `@State` that logs —
  accessor + peer, the property stays LIVE.** The accessor role rewrites
  the property itself: an init accessor (`@storageRestrictions(initializes:
  count_storage)`) funnels the inline default into the storage, `get`
  reads `count_storage.wrappedValue`, and the single logging point is the
  `nonmutating set`. Peers: `private var count_storage: State<Int>`
  (initialized via the init accessor), `private let log_count = TestLog()`,
  and `` `$count` `` — a `Binding` routed through
  the property itself, so direct writes and binding writes log through the
  same setter. Everything generated is `private` — `$name` included; only
  the host's own `body` wires it. Type from the annotation or the shared
  three-literal inference (`inferredLiteralType`).
- **`@TestAction var save: (Item) -> Void = { _ in }` — the property's own
  getter IS the logged action, no `$name`, no setter.** Accessor + peer:
  an init accessor funnels the inline default into a `save_storage` peer,
  and the getter returns a wrapper closure logging an arity-shaped payload
  — `String(describing:)` of `()` for zero args, of bare `a0` for one, of
  a tuple beyond — then
  forwarding with `return`/`try`/`await` each added iff the declared type
  needs it. The getter extracts `log` (the resolved sink closure,
  `@MainActor` hence Sendable) and `storage` into locals first, so the wrapper captures
  two plain values and never `self` — deliberate: no view copy dragged
  into `async`/`@Sendable` action closures, and Environment resolution
  happens at the view copy's install either way (an env change re-renders
  `body`, minting a fresh wrapper — same net freshness as a self-capturing
  read). `var`, not `let` — the compiler refuses accessor expansion on
  `let` (dead ends below); a `let` closure is skipped like any other
  unspellable shape.
- **Every generated DynamicProperty is an EXPLICIT stored field, never
  wrapper sugar — a compiler crash forces this.** A macro-generated
  `@Environment(\.testLog) private var log_x` SILGen/IRGen-crashes swiftc
  6.4 (signal 11 emitting the wrapper's synthesized getter — verified
  directly; hand-written identical source compiles fine, and it crashes
  with `\.self`/`EnvironmentValues` too, so it's not the closure-typed
  entry). The explicit `private let log_x = TestLog()` field dodges it —
  `TestLog` is a `DynamicProperty` wrapping the hand-written sugar, and
  SwiftUI installs DynamicProperties by field type, not wrapper syntax, so
  injection stays reactive (nested installation verified live by the UI
  tests). Same pattern as `State<T>` for the value storage.
- **The property's own access picks its role, and no init is ever
  needed** — Swift's synthesized memberwise init constructs the host
  bare, cross-file. Internal + defaulted → a defaulted memberwise-init
  parameter (`TestSupportTests`' probe hosts); private + defaulted →
  excluded from the memberwise init entirely, a sealed source of truth
  that logs — what `@Shell` generates on `Core` and what scenarios
  declare (verified directly: the init stays internal). The generated peers never become parameters either way: the
  storage is subsumed by the init accessor and `log_x` carries a default.
  Dollar names are legal from
  macros: `names: prefixed($), prefixed(log_)[, suffixed(_storage)]`.
- **The seam: `testLog` installs, `TestLog` reads.** The `\.testLog`
  `@Entry` and its `ComparableLog` value are internal — a struct, not a bare
  closure-typed entry (which warns that dependents may invalidate on every
  update; always-equal is honest for a seam installed once). `TestLog` is a
  `DynamicProperty` wrapping the `@Environment` read; the macros generate it
  as an explicit stored field (`private let log_x = TestLog()`) and its
  `wrappedValue` IS the sink closure, so generated call sites are direct
  closure calls. The sink is `@MainActor (String, String) -> Void` —
  globally-isolated function types are implicitly Sendable, every sink runs
  serialized on the main actor. Payloads are `String`, not `Any`: an `Any`
  holding a class would trip region-isolation at the `@Sendable async`
  wrapper's `await log(...)` — an error INSIDE the expansion a user can't
  fix — and `String(describing:)` at the call site freezes the value the
  moment it happens, the snapshot contract. Sync wrappers/setters and plain
  async wrappers call the sink directly (a non-Sendable closure inherits the
  host's main-actor isolation; an `await` there draws the unnecessary-await
  warning — verified directly). Only a `@Sendable async` wrapper — the one
  shape that can't inherit the isolation — `await`s the log IN ORDER before
  forwarding; deliberately no fire-and-forget `Task`, which could reorder
  log lines against synchronous state writes. Outside a live view the entry
  reads its no-op default — but SwiftUI flags the uninstalled read as a
  runtime issue, so package unit tests stop at the generated surface and
  seed reads (`TestSupportTests.swift`, `@MainActor` suite) while logging
  and forwarding are verified live by the example
  app's UI tests. Expansion shapes: `TestSupportSyntaxTests.swift`.
- **Log effects, never getters — the criterion is who owns the invocation
  timing.** Setters and action calls fire when the component's own logic
  decides — deterministic, so snapshot-diffable. Getter reads (the state
  `get`, a binding's `get`, an action property being wired into a child)
  fire when SwiftUI's render scheduler decides — real events, but their
  count varies by OS/device/render strategy, and one non-deterministic
  line poisons the all-or-nothing snapshot diff. A test that needs "was
  this read?" uses a use-site spy binding asserted with a predicate, not
  a snapshot line.
- **Dead ends worth remembering if anyone revisits an in-place rewrite:**
  the compiler hard-refuses accessor macros on `let` (`cannot expand
  accessor macro on variable declared with 'let'` — verified directly, no
  role gets around it); `@State` sugar on a generated storage peer breaks
  `@storageRestrictions(initializes:)` subsumption (the wrapper's own `_x`
  backing landed as an extra memberwise parameter — verified directly);
  and an init-accessor property's inline default runs at the top of EVERY
  init, so `let` storage peers double-initialize (verified directly).

## @UnstructuredTask — tricky points

The third macro in the `@TestState` family (`UnstructuredTaskMacro.swift`;
declaration plus the runtime `TaskStorage`/`CancellableTask` in
`Sources/CoreFlow/UnstructuredTask.swift`) — a view-owned slot for a
cancellable unstructured `Task` that logs. Ported from the standalone
`~/dev/TaskState` package (there a runtime `@propertyWrapper` around
`@State`-held class storage); made a per-property macro here specifically
so mutations log the property's ACTUAL name through `\.testLog`, which a
plain wrapper can never know. Named for what it stores — the wrapper's job
is giving an unstructured task the two structure guarantees it lacks
(cancel on replace, cancel on view teardown) — and to keep a
one-letter-apart `@TaskState`/`@TestState` pair out of the API.
Production-safe, not test-only: the uninstalled sink is a no-op.

- **Accessor + peer like `@TestState`, but the property becomes COMPUTED —
  no init accessor, and the task always starts `nil`.** The storage peer
  self-initializes (`= State(wrappedValue: TaskStorage())`), so the
  property is never a memberwise-init parameter whatever its access level —
  `@TestState`'s internal-vs-private role split doesn't exist here. The
  initial value isn't configurable by design, and the guard deliberately
  does NOT check for an initializer: accessors on an initialized `var` are
  the compiler's own "variable with accessors can't have an initial value"
  error at the right line, where a skip would leave a plain, silently
  unmanaged stored property behind.
- **Lifecycle lives in the `TaskStorage` box, one choke point.** A CLASS in
  `State`, not `State<Task?>`: `willSet` cancels the replaced task, `deinit`
  cancels the live one when SwiftUI releases the storage (a value in `State`
  has no teardown hook). The `willSet` is equality-guarded — `Task`'s
  stdlib `Equatable` is identity — so a self-reassignment (binding
  round-trip, defensive `x = x`) is not a cancel; that's why
  `CancellableTask` refines `Equatable`. `@Observable` (with `willSet` and
  `deinit` — both compile and fire under the macro, locked by
  `TaskStorageTests`) so a `body` reading the property re-renders on task
  change.
- **The storage element is the annotation minus its `?`, never a parsed
  `Task<Success, Failure>`.** `TaskStorage<T: CancellableTask>` (public
  protocol: `cancel()` + `Equatable`, conformance on `Task` itself) means
  the macro only unwraps `OptionalTypeSyntax` — a typealiased task type
  (`VoidTask?`) works, and there's no generic-argument parsing to get
  wrong. Only the sugared `T?` counts: IUO (`T!`) and long-form
  `Optional<T>` are skipped shapes. Both types public: generated code lands
  in the consumer's module.
- **Payload is `"task"`/`"nil"`, not `String(describing:)`.** A described
  `Task` isn't snapshot-stable, and one nondeterministic line poisons the
  all-or-nothing log diff — same criterion as the getters-don't-log rule.
- **Under `@Shell` it's deliberately NOT whitelisted**: it rides rule 2 as
  an unknown wrapper — the verbatim copy re-expands the macro on `Core`
  (locked by `UnstructuredTaskTests`), and the computed property stays out
  of the memberwise init on both types, so the twin cancels and logs
  identically with nothing to substitute.

## @TestFocusState — tricky points

The fourth macro in the `@TestState` family (`TestFocusStateMacro.swift`;
declaration in `TestFocusState.swift`) — a drop-in `@FocusState` that logs,
and `@Shell`'s substitution for `@FocusState` on `Core` (the `@State →
@TestState` rename treatment exactly: wrapper token renamed on the host's
own line, private required via `sourceOfTruthMustBePrivate`).

- **Computed over a self-initialized REAL `FocusState<T>` peer** (`private
  let name_storage: FocusState<T> = FocusState()`) — accessor + peer like
  the family, but no init accessor: `@FocusState` has no
  `init(wrappedValue:)`, so a host line never carries a default and there
  is nothing to funnel; the property is never a memberwise-init parameter
  whatever its access level (same shape as `@UnstructuredTask`). **Bad
  shapes are refused by the macro itself — expansion THROWS**
  (`MacroExpansionErrorMessage`, a compile error at the attribute) on
  `let`, an inline default, a missing annotation, or a
  non-single-stored-instance-var shape — deliberately NOT the family's
  silent-skip policy, because here a skip can COMPILE: `@TestFocusState
  var focus = false` skipped is a plain, unmanaged stored property that
  never logs, and the compiler accepts macro-added `get`/`set` accessors
  on an initialized `var` without complaint (verified directly — the
  "variable with accessors can't have an initial value" error does NOT
  fire for macro-added accessors on this toolchain, so "let the compiler
  catch it" cannot work; note this contradicts the older verified claim
  recorded for `@UnstructuredTask`'s written-default case, which predates
  this toolchain). The accessor role throws, the peer role stays silent
  (`try?`) so the error reports once. `FocusState()` exists only for
  `Bool` and optional values, so any other annotation still fails in the
  compiler's own words on the generated peer, exactly like the live
  wrapper.
- **`$name` forwards the REAL `FocusState<T>.Binding`**
  (`name_storage.projectedValue`) — `.focused(_:equals:)` demands that
  exact nominal type, and it cannot be wrapped or fabricated: verified
  directly against the SDK swiftinterface, `FocusState.Binding` is
  `@frozen @propertyWrapper` exposing exactly `wrappedValue`
  (`nonmutating set`) and `projectedValue` (itself), with NO public
  initializer. Deliberate consequence: writes through the binding — the
  SYSTEM moving focus on tap, keyboard dismissal, … — don't log; only
  programmatic property writes do. **The property logs, the projection
  wires.** Same criterion as getters-don't-log: scheduler-owned timing has
  no place in an all-or-nothing snapshot diff. (This is the one family
  member whose `$name` can NOT route through the property the way
  `@TestState`'s does — the projection must be the native type.)
- **Receiving-side support (a host storing `FocusState<T>.Binding`) was
  designed at length and deliberately dropped.** The blocking fact: a
  stored native binding's writes are uninterceptable — `name.wrappedValue
  = x` executes inside Apple's sealed type after the getter has returned
  it, and no macro role can wrap a foreign type's member setter — while
  every parity-surface stand-in changes either the declaration type, the
  construction label, or the body spelling. Owner-side only; a child
  needing focus gets `.focused` attached at the owner's use site.
- **Unhosted, reads return the wrapper's reset value and writes log then
  no-op** like the live wrapper's own — the log still records the intent,
  so a directly-constructed `Core` can assert "logic tried to focus X"
  with zero view machinery. Package tests stop at the lifecycle
  boundary — no unit test evaluates unhosted wrapper behavior; what's
  locked here is the expansion shape (`TestSupportSyntaxTests`) and the
  substitution + the non-private diagnostic (`ShellSyntaxTests`);
  read/write/projection parity holds by type identity (`name` reads the
  bare value on both sides, `$name` is the same nominal
  `FocusState<T>.Binding` on both). Live focus movement and logging are
  the example app's story.

## @Capability — tricky points

`member` macro that bundles every eligible *computed* property/method into a
`Capability` typealias + `capability` computed property — Scott Wlaschin's
capability-based design ("Designing with capabilities", fsharpforfunandprofit.com/cap):
hand a consumer exactly the functions it may call, as plain values, not the
whole object. Entry point + collection +
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
