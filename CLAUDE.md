# CoreFlow maintainer context

CoreFlow is one Swift package with one macro-plugin target and one library
product. It ships independent Swift macros plus two small runtime utilities,
`QueryCore` and `Reflector`; consumers add one dependency and receive the whole
package.

## Session contract

### Package identity and supported toolchain

Consumer dependency:

```swift
.package(url: "https://github.com/sisoje/swift-core-flow.git", from: "1.0.0")
.product(name: "CoreFlow", package: "swift-core-flow")
```

The `package:` argument is the URL-derived SwiftPM identity `swift-core-flow`,
not the manifest's declared name `CoreFlow`. This exact pair was verified with a
real scratch-package resolution; SwiftPM selected CoreFlow 1.0.2 and swift-syntax
603.0.2. The old `package: "CoreFlow"` spelling fails with
`unknown package 'CoreFlow'` and names `swift-core-flow` as valid.

The package targets Swift 6.3 (`swift-tools-version: 6.3`) in Swift 6 language
mode with strict concurrency. It supports swift-syntax
`600.0.0..<700.0.0`; the APIs used here are stable across the Swift 6.x line.

### Commands

- Build and test: `swift build && swift test`
- Format source and tests:
  `swift format --in-place --recursive Sources Tests`
- Regenerate the example app: `cd CoreFlowExample && sh generate.sh`
- Verify the generated example and UI tests:
  `cd CoreFlowExample && sh test.sh`

### Documentation and verification rules

- `CLAUDE.md` is self-sufficient agent context and maintainer specification. A
  session reading only this file must know every rule, verified fact, and rejected
  design required to change the package safely.
- `README.md` is the public per-macro reference. Its introduction links the
  SwiftUI Data Flow Masterclass published on Medium: nodes, waves, boundary
  events, the shell/core split, and execution-log testing, taught macro-free as
  a manual two-view split. The macros mechanize that same split—one conceptual
  story with different vehicles.
- `CoreFlowExample/SPEC.md` is the source specification for the example app; its
  Swift sources regenerate from that document.
- Documentation states facts and current decisions, not removal chronology.
  Compress without losing qualifications; keep references at the bottom; do not
  name an API before its chapter introduces it.
- Macro-expansion snapshots prove emitted syntax only. Claims about type
  checking, overload resolution, synthesized initialization, isolation, runtime
  behavior, or SDK interfaces require real compilation or execution against the
  package and pinned toolchain.
- Expansion tests are whitespace-sensitive. When generated output changes,
  compare the displayed code and `assertMacroExpansion` expectation with the
  actual expansion rather than hand-correcting plausible syntax.
- Every intermediate documentation commit must leave this file fact-complete.
  Move a fact by deleting its old text and adding its new home in the same
  commit. Duplication is temporarily acceptable; an information gap is not.

## Repository map

### Package targets

| Target | Kind | Contents |
|---|---|---|
| `CoreFlowMacros` | macro plugin | every macro's implementation, one `@main` `CompilerPlugin` listing all of them. One file per macro (`FlowableMacro.swift`, `ShellMacro.swift`, `CapabilityMacro.swift`, `PickMacro.swift`, `TestSupportMacros.swift` — that one holds `@TestState` + `@TestAction` — `TestFocusStateMacro.swift`, and `UnstructuredTaskMacro.swift`), plus shared stored-property collection + rendering (`StoredProperty.swift`, `MemberMacroEntry.swift`, `FieldRendering.swift`, `FlowableRendering.swift`) that `@Flowable` builds on and `@Shell` reuses (`ShellRendering.swift`), and TuplePicker's own parsing (`KeyPathPick.swift`, `TuplePickerSupport.swift`) |
| `CoreFlow` | library (the one product) | every macro's public attribute/expression declaration, one file per macro (`Flowable.swift`, `Shell.swift`, `Capability.swift`, `TuplePicker.swift`, `TestSupport.swift` — `@TestState`/`@TestAction`, `testLog`, `TestLog` — `TestFocusState.swift`, and `UnstructuredTask.swift` — `@UnstructuredTask` plus its runtime `TaskStorage`/`CancellableTask`), plus two small non-macro additions: `Reflector.swift` (pairs with `@Flowable`, see below) and `QueryCore.swift` (`@Query`'s drop-in stand-in on `Core`, see the `@Shell` notes) |
| `CoreFlowTests` | test (XCTest + swift-testing, same target) | all coverage: `assertMacroExpansion` per macro, plus real-compiled end-to-end suites (TuplePicker, Reflector, Shell's `Core`, `QueryCore`, the test-support macros) |

Per-macro target/product sets were considered and rejected. Their ceremony is
not worth dependency granularity no consumer needs. Adding a macro means adding
files and registrations inside the existing target pair, not adding products or
targets.

### Shared implementation and adding a macro

To add `Foo`:

1. Add `FooMacro.swift` to `CoreFlowMacros` with the appropriate macro role.
2. Register the implementation in `Plugin.swift`'s `providingMacros`.
3. Add `Foo.swift` to `CoreFlow` with the public `@attached` or `@freestanding`
   declaration pointing to
   `#externalMacro(module: "CoreFlowMacros", type: "FooMacro")`.
4. Add expansion, diagnostic, and real-compiled tests as the feature requires.

Macros derived from stored properties must use `validatedProperties` in
`MemberMacroEntry.swift`, the `StoredProperty` model, and the shared renderers
rather than re-deriving collection rules. `@Flowable` owns
`FlowableRendering.swift`; `@Shell` reuses that collection through
`ShellRendering.swift`.

`StoredProperty` deliberately carries two channels:

- parsed fields—`name`, `type`, `defaultValue`, `wrapperName`, `isLet`, and
  `isPrivate`—for `@Flowable` initialization/typealias rendering and `@Shell`'s
  substituted rows;
- raw `varDecl` and `binding` syntax for `@Shell`'s verbatim-copy path.

Never rebuild a verbatim declaration from parsed pieces. Copies re-render the
host's syntax so attribute arguments, defaults, observers, and unknown wrapper
spellings survive unchanged.

Everything generated for a `@Flowable` type comes from its one attribute. There
is deliberately no second macro for `makeFlow(_:)`/`InFlow`, and no initializer
taking the whole tuple; `makeFlow(_:)` is a static factory. A future tuple-input
feature should build on `renderMakeFlowFactory`, which already owns
tuple-versus-bare-type collapse.

A macro combining outputs from existing macros must collect stored properties
once and call the shared renderers directly. Do not implement a composite macro
by stacking existing attributes: stacking works only while generated member sets
do not collide, and it repeats collection and diagnostics for the same fields.

### Example app and generated-source workflow

`CoreFlowExample` is an xcodegen project whose checked-in source-of-truth files
are exactly `project.yml`, `test.sh`, `generate.sh`, and `SPEC.md` (plus repository
metadata such as `.gitignore`). Generated Swift sources and the Xcode project may
also be present in the working directory. Swift sources are collapsed into
`SPEC.md` and regenerated with `sh generate.sh`; keep `project.yml`, `test.sh`,
and `generate.sh` verbatim as part of the specification. Run `sh test.sh` after
every regeneration.

`CoreFlowExampleUI` is a real SPM library containing every component, one source
file per host/scenario/`#Preview` after generation:

- reading-list components use internal `@Shell` hosts with SwiftData `@Query`
  and `@AppStorage`;
- the public `@Flowable @Shell ReadingListScreen` composes them and is the app's
  single entry point;
- `BookStore` is a closure capability behind a public `@Entry`, mocked by
  construction and wrapped in an always-equal `Equatable` value;
- five internal components exercise plain `@GestureState`, custom
  `@GestureState(reset:)`, `@FocusState`, a `ViewModifier` host, and an async
  throwing action.

`RealApp` (`CoreFlowRealApp`) imports the library normally, uses live wrappers,
and injects the live `BookStore` through a `ViewModifier` that reads the real
`modelContext`. `TestApp` (`CoreFlowTestApp`) uses `@testable import` to reach
internal scenarios. The `SCENARIO` environment variable selects one;
`defaultScenario` is used when it is absent so Cmd-R works.

Every scenario hosts a `Core`, often bare `Core()`: substituted `@TestState`
fields own and log their state. A scenario supplies only caller-owned boundaries:
`@TestAction` closures, data arguments, and genuine `@Binding` backings. The app
installs one sink on the root view with `.testLog { … }` and appends each
`(name, value)` to plain `@State` at the write site.

The scenario `Group` exposes the log through accessibility without a phantom
view or opacity trick:

- `.accessibilityElement(children: .contain)`;
- identifier `log`;
- names JSON in `label`;
- values JSON in `value`.

JSON preserves arbitrary description content. Each XCUITest waits for its own
finish signal with `log.wait(for: \.label, toEqual:)`; because names are fixed
identifiers and raw-string comparable, that equality is also the names
assertion. It then decodes `app.logValues` as `[String]` and compares the values.
This is intentionally an in-process live assertion, not a recorded snapshot
file: there is no record/re-record cycle and one unstable description cannot
poison a file-wide diff. Streaming values such as drag distances remain
predicate-asserted.

`test.sh` passes `-collect-test-diagnostics never`. Simulator diagnostic
collection timed out once at exactly 600 seconds on the Xcode beta; disabling
that post-test collection makes the run deterministic without changing the test.

## Package-wide invariants

### Syntax, collection, and type inference

Macros receive syntax, not a type checker. Stored-property macros share
`validatedProperties`/`collectStoredProperties`; they do not independently infer
semantic types. The only types inferred from expression syntax are bare `Bool`,
`Int`, and `String` literals, through `inferredLiteralType` in
`StoredProperty.swift`. Calls, identifiers, `nil`, collection literals, and other
expressions require explicit annotations. Native wrappers that determine their
own type, such as `@Namespace`, remain a separate case: a verbatim copy preserves
the wrapper declaration and relies on the same native inference as the host.

Each API keeps its local consequence of this rule: `@Flowable`'s inferred
`let seed = 42` reaches Swift's `let`-reassignment error; `@Shell` needs a known
type only for substituted rows; `@Capability` requires explicit computed-property
result types; and `@TestState` accepts an annotation or the same three literals.

### Ownership and access

Non-private stored properties are caller-supplied data. Private wrapped
properties are runtime-owned state or machinery. Plain private storage is
refused with `plainPrivatePropertyNotAllowed`: opaque state that neither flows in
nor belongs to a runtime wrapper has no role in this model.

The source-of-truth wrappers `@State`, `@FocusState`, `@AppStorage`,
`@SceneStorage`, and `@Query` must be private
(`sourceOfTruthMustBePrivate`). Caller-supplied `@Binding` and `@ViewBuilder`
must not be private (`callerSuppliedWrapperMustNotBePrivate`, through
`property.isCallerSuppliedWrapper` in `StoredProperty.swift`). `private(set)` and
`fileprivate(set)` deliberately follow the same diagnostics; setter-restricted
stored data has no separate role. Unknown wrappers carry no package-wide privacy
rule, because `@Shell` must preserve wrappers it does not understand.

### Diagnostics before rendering

Invalid user shapes diagnose during collection or throw from expansion. Never
silently skip a malformed declaration that could compile as unmanaged stored
state. Renderer assertions are developer tripwires only; the user-facing path
must already have produced a diagnostic. Diagnostic locations anchor at the
relevant property or attribute, not an arbitrary generated line. Each macro's
section retains its exact diagnostic and the local reason the malformed shape is
dangerous.

### Parsed fields and verbatim syntax

Parsed `StoredProperty` fields drive generated declarations and initializers;
raw `varDecl`/`binding` nodes drive verbatim copies. Never reconstruct a
verbatim declaration from parsed pieces. Everything lives in one macro module,
so shared collectors and renderers need no cross-target `public` API and no
extra target wiring—the reason reuse is frictionless rather than merely
possible.

### Generated-code verification

`assertMacroExpansion` locks emitted syntax and whitespace only. Real
compilation is required for overload resolution, synthesized initialization,
macro stacking, isolation, SDK interface parity, and generated-member usability.
Runtime tests own logging order, binding write-through, lifecycle, focus,
scenarios, and UI behavior. On a formatting-only snapshot failure, compare with
the actual expansion; never repair generated output by intuition. Diagnostic
specs anchor `line`/`column` at the property's name, not the line start.

## `@Flowable`

### Contract

`member` macro that writes a memberwise `init` at the type's own access
level, for a struct, class, or actor — plus `makeFlow(_:)`, a static
factory building `Self` from the same properties bundled as one *unlabeled*
tuple, spelled inline in the signature (deliberately no typealias naming
it), and `InFlow`, the labeled tuple typealias naming the shape (readable,
`Mirror`-reflectable). Entry point:
`Sources/CoreFlowMacros/FlowableMacro.swift`. Rendering: all three —
`renderFlowable` (the init), `renderMakeFlowFactory`, and
`renderInFlowTypealias` — live in
`Sources/CoreFlowMacros/FlowableRendering.swift`; the last two are called
from inside the first, so one expansion always produces all three together
(or just the bare init, with zero properties to alias/build from).

### Stored-property eligibility

The package-wide syntax and ownership invariants define collection. For
`@Flowable`, non-private stored properties participate; computed and
`static`/`class` members are skipped; stored properties with only
`willSet`/`didSet` observers participate. A property needs an explicit type or
one of the three bare literal defaults. The local edge case remains important:
`let seed = 42` passes the missing-type check because `Int` is inferable, then
fails with Swift's own `let`-reassignment error. Use `static let` for constants.

Plain private storage, non-private source-of-truth wrappers, and private
caller-supplied `@Binding`/`@ViewBuilder` declarations retain the shared
diagnostics above. Other private wrappers are excluded from the initializer and
remain runtime-owned.

### Generated initializer

The initializer mirrors the attached type's access and works uniformly for a
struct, class, or actor—including an `@Observable final class` that Swift would
not otherwise give a memberwise initializer.

- **Function-typed properties get `@escaping`**, attributed types included
  (`@MainActor () -> Void`, `@Sendable (Int) -> Void`). Optional closures
  (`(() -> Void)?`) get no `@escaping`—they are already escaping, and adding the
  attribute is a compile error.
- **Optional `var` gets a `nil` parameter default** for both `T?` and `T!`,
  mirroring Swift's synthesizer: the property is implicitly nil-initialized, so
  no explicit `= nil` is required. The IUO case is deliberate and contrasts with
  `@UnstructuredTask`, which rejects `T!`.

### SwiftUI fields
- **`@Binding` is the kept exception:** threaded as a projected `Binding<T>`, assigned
  `self._x = x`.
- **`@ViewBuilder` has two forms, and must be a `let`.** Stored closure
  `let vb: () -> Content` → `@ViewBuilder vb: @escaping () -> Content`,
  `self.vb = vb`. Stored value `let vb2: Content` → `@ViewBuilder vb2: ()
  -> Content`, `self.vb2 = vb2()` — the init *calls* the builder. A
  `@ViewBuilder var` is refused (`viewBuilderMustBeLet`, shared
  collection, so it fires under `@Shell` too): builder content is
  caller-supplied through the generated init and never reassigned.
### `makeFlow(_:)`

The factory is a `static func` (not a second `init`) building
`Self` from the same property collection as the init above, bundled into one
unlabeled tuple parameter spelled inline in the signature:
- **A static func, not a delegating `init`, specifically to work uniformly across
  struct/class/actor.** A second `init` calling `init(...)` needs the
  `convenience` keyword on a class/actor and drags in Swift's designated/convenience
  init rules; `Self(...)` inside a plain static function sidesteps that entirely.
- **The parameter is an *unlabeled* tuple** — `(T, U)`, not `(x: T, y: U)` —
  **carrying no typealias that names it**: a second name for the shape earns
  nothing (`InFlow` below feeds the parameter with no conversion and is the
  better spelling for storing/diffing, and generic code can't constrain on a
  generated member typealias — no protocol declares one).
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
- **Exactly one property collapses the parameter to the bare field type, not a
  1-tuple.** Swift has no 1-tuples — `(x: T)` as a type collapses to plain `T`,
  no `.x` accessor — and `flow` is then the one field's value directly, no
  positional index: `Self(value: flow)`. This single-field collapse is also the
  one case that needs `@escaping` (the closure becomes a direct function
  parameter; inside a real tuple a closure is already escaping, and `@escaping`
  on the tuple parameter would be ill-formed).
- **Zero properties** → no factory — nothing to build from, and the init
  above already covers the zero-property case on its own (`init() {}`).
- **No per-field defaults.** Tuple element types can't carry `= default`, so an inline
  `var` default and optional-implies-`nil` are both *dropped* here — unlike the init,
  which keeps them.
- **`@ViewBuilder` wrapping is ignored in the parameter.** A stored-value field
  (`@ViewBuilder let footer: Content`) keeps its own type (`Content`) in the
  tuple, *not* the `() -> Content` builder the init uses right above it. The init
  wants that wrapping — it's what buys trailing-closure syntax at the call site. That
  reason doesn't exist for a tuple type (no parameter position for a trailing closure
  to attach to), and a closure isn't `Equatable` or comparable.
  `baseTypeText` (in `FieldRendering.swift`) takes a `wrapViewBuilder` flag for
  exactly this — the init's own rendering passes `true` (the default), the flow
  rendering passes `false`. `makeFlow(_:)` re-wraps the plain value back into a
  trivial closure for the init: `footer: { flow.2 }`.
- **Forwards each field directly** — `Self(x: flow.0, y: flow.1)` — not
  the `[layout].map(Self.init).first!` trick an *unapplied* `Self.init` reference
  needs to accept a tuple positionally. The macro already knows every field's
  position, so it just spells out the call. Fields are read positionally
  (`flow.0`, `flow.1`, … in field order), since the tuple is unlabeled.
- **Positional, unlabeled parameter (`_ flow:`)** — a deliberate naming
  choice: the factory is spelled `makeFlow(_:)`, called as
  `Type.makeFlow(someFlow)`.

### `InFlow`

The typealias is `makeFlow(_:)`'s parameter shape, labeled, same
collapse/zero rules and same `wrapViewBuilder: false`:
- **Exists for readable spelling and real `Mirror` support.** Verified
  directly: `Mirror(reflecting:)` reports each field's actual name over a
  *labeled* tuple, only positional labels (`.0`, `.1`) over an *unlabeled*
  one — the unlabeled parameter alone can't support generic field
  reflection (see `Reflector` below), `InFlow` can.
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

### Zero-, one-, and many-field shapes

| Participating fields | Initializer | `makeFlow(_:)` | `InFlow` |
|---|---|---|---|
| zero | `init() {}` | absent | absent |
| one | one parameter | bare field type | bare field type |
| many | memberwise parameters | unlabeled tuple | labeled tuple |

The table summarizes the shapes; the mechanism and edge cases above remain the
source of truth.

## `@Shell`

### Contract

`@Shell` is a separate `member` macro, not a mode of `@Flowable`; either or
both may be attached. It collects through the shared `validatedProperties`
path. `Sources/CoreFlowMacros/ShellMacro.swift` is the entry point;
`renderShell` in `Sources/CoreFlowMacros/ShellRendering.swift` owns rendering.

The macro generates an always-internal nested `Core`, never annotated with
`@Flowable`: the host's runnable twin, or functional core to its imperative
shell (Bernhardt/Wlaschin/Seemann; links in the README References). The
masterclass teaches the same split by hand. The host keeps its hand-written
implementation; tests and scenarios construct `Core` directly. No generated
`core` property captures a live host.

`Core` is a testing/preview seam, never part of the host's public API—even
when the host itself is public. Consumers need only the host; the twin belongs
to the defining module and its tests through same-module access or
`@testable import`. Field access follows the transformation: the `@State`
substitution remains private, `@Binding` and `@QueryCore` substitutions are
internal, and verbatim copies retain their access with `public` erased.

`Core` keeps the same logic while turning runtime boundaries into test
boundaries: owned state logs writes, external sources become supplied data, and
effects remain closures. Supplying external storage and fetched data also
severs their event channels: no storage change or fetch notification can
trigger a wave mid-test.

`Core` is nominal because a tuple cannot carry copied members, conform to
`View`/`ViewModifier`, or later conform to `Equatable`, `Codable`, or a shared
snapshot protocol. Verified directly: `type '(x: Int, y: String)' cannot
conform to 'Equatable' — only concrete types such as structs, enums and classes
can conform to protocols`. Zero eligible fields still produce `struct Core {}`
with Swift's synthesized empty initializer.

Because `Core` is internal and unreachable from the release product, the
optimized release binary pays zero bytes for its code, metadata, and conformance
record.

### Stored-property transformation

`renderShell` applies two rules in order: substitute only the explicit
`isSubstitutedOnCore` whitelist, then copy every other declaration from its raw
syntax. Unknown wrappers are never guessed.

| Host declaration | `Core` declaration | Why |
|---|---|---|
| private `@State` | private `@TestState`, inline default retained | Node-owned state stays sealed; writes become evidence. |
| private `@FocusState` | private `@TestFocusState` | No public focus-binding initializer exists; instrument the real hosted peer. |
| private `@AppStorage` / `@SceneStorage` | `@Binding` | External storage becomes caller-supplied; persistence keys disappear because the twin does not persist. |
| private `@Query` | `@QueryCore` | Fetched data becomes a bare supplied value without a SwiftData stack. |
| every other declaration, wrapped or plain | verbatim copy, with `public` erased | Preserve caller data or runtime machinery where no designed substitution exists. |

The whitelist is the only wrapper set this package knows. Each substitution
buys a log, an injectable boundary, or a bare value. The shared `isPrivate`
check matches the `private` keyword regardless of its `(set)` detail, so
`private(set)` and `fileprivate(set)` deliberately follow the same diagnostics.

### Substituted wrappers

- **The mapped rows, and what each substitution buys.** `@State` →
  `@TestState private`: the drop-in that keeps the field live while
  logging every mutation — ownership unchanged (an internal source of
  truth is never a caller's; moving it up would falsify the component's
  data flow just to observe it), the write site now emits evidence. The host's
  inline default is required by `stateNeedsInlineDefault` in `ShellMacro.swift`:
  the initial value is part of the component's definition, never a test
  parameter. The check uses the carried `binding`; `@Flowable` renders nothing
  from private `@State`, as locked by `FlowableTests`.
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

### Copied verbatim

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

The rule-2 renderer asserts that a plain private field never reached rendering;
the `@State` rename asserts `isPrivate`. These are developer tripwires backed by
`plainPrivatePropertyNotAllowed` and `sourceOfTruthMustBePrivate`; users receive
collection diagnostics, never a macro crash. Privacy stays on verbatim copies:
erasing it would resurface a wrapper-typed memberwise-initializer parameter.
Plain fields retain the host's own `let` or `var`; a defaulted `let` remains a
constant and drops out of `Core`'s memberwise initializer exactly as it does on
the host.

### Copied members and synthesized initialization

Every non-stored member comes from `copiedMemberSources` in `ShellMacro.swift`:
`body`, helpers, methods, `static` members, and nested types. Initializers alone
are not copied because one would suppress Swift's synthesized memberwise
initializer. `testHelpersStaticMembersAndNestedTypesAreCopiedButInitsAreNot`
locks that boundary in the expansion suite.

No hand-written initializer is needed. Verified directly, Swift's memberwise
synthesis gives a wrapper-typed parameter when a wrapper lacks
`init(wrappedValue:)` (`@Binding`), a wrapped-value parameter when it has one
(`@QueryCore`, `@Bindable`), and a builder-closure parameter for a stored
value-form `@ViewBuilder`. Copied members retain their access modifiers; a
`public` member remains legal but is capped by internal `Core`.

- **Zero eligible fields still generates a (near-empty) `Core`** —
  `struct Core {}` — no diagnostic, mirroring `@Flowable`'s own graceful
  zero-property `init()` rather than `@Capability`'s "zero is an error"
  stance (Swift synthesizes the empty `init()` here on its own).

### Host-kind detection and read-surface parity

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

### Construction and binding strategies

Mocking happens at construction, with no post-construction swapping. Tests back
bindings with `.constant`, `Binding(get:set:)`, or a hand-written, file-scoped
`@Observable @MainActor` model whose `Bindable(model).x` projection produces a
real write-through binding (`handWrittenObservableModelBacksABinding` in
`ShellTests.swift`; `@Observable` cannot attach to a local type). Raw backing
access stays an explicit same-file escape hatch; see `QueryCoreTests.FakeCore`.

Generated binding-wiring was rejected because these situational lines belong at
the use site. If revisited, preserve three verified constraints: attached macros
expand inside another macro's output; a generated class needs explicit
`@MainActor` because nested types do not inherit enclosing View-conformance
isolation; and an observable class must be a sibling of `Core`, because nesting
it inside `Core` makes `@Observable`'s extension half fail at link with a missing
conformance descriptor.

### Preview and cross-expansion limits

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

### Deliberately unmapped: `@StateObject` / `@ObservedObject`

Neither wrapper is on the whitelist, deliberately—not as a gap to fill later.
Both are Combine-era `ObservableObject` wrappers: ViewModel-shaped shared
references whose aliases can mutate state around `Core`'s boundary, exactly the
model this package's plain-data flow avoids. They are copied verbatim and receive
no stand-in; model testable state with the mapped wrappers instead. See the
`swiftui-mv-architecture` skill for the broader argument.

### Verified rejected designs

This placement is interim. Checkpoint 6 moves these complete dead ends to the
approved top-level `Rejected designs and dead ends` section without changing
their substance.

- **The delegation redesign was built, run green, and abandoned — the
  full map, so nobody re-walks it.** The idea: Core as the ONE
  implementation (fields generated, logic hand-written in
  `extension Host.Core`, host body generated as a memberwise delegation
  `Core(items: items, isPinned: $isPinned, …)`), buying exact line
  coverage since the executed logic is real source. Verified en route:
  hand-written extensions DO resolve macro-generated nested types
  (`extension Card.Core` compiles — the file-scope type-position failure
  does not extend to extension positions), and a mirror macro is
  impossible in every form — "macro expansion cannot introduce extension"
  (exact compiler error) bars emitting `extension Host { }` from any
  role, and no macro can see sibling source anyway: whoever can see the
  extension's members can't emit the host extension, whoever could emit
  can't see. Why abandoned: production Core carries @TestState (host
  @State becomes a dead template — the declaration lies), the host has no
  visible body, live channels that don't fit a memberwise init silently
  drop (`fetchError`: the bare-value @QueryCore param can't carry the
  live Query's error — production Core would read nil), and the "pure
  Core" escape (hoist all truth to the shell, inject bindings) unravels
  on the sealed `FocusState.Binding`, unhoistable `@GestureState`, and
  the loss of Core-owned logging. The copy design stands; exact coverage
  of the copied body waits on compiler-side instrumentation of expansion
  buffers (bullet below).
- **Coverage cannot credit the copied body — verified directly, and
  `#sourceLocation` can't fix it.** Swift emits NO coverage instrumentation
  for functions in macro-expansion buffers on this toolchain: `Core.body`
  has zero counters in the profile data, under any filename. Wrapping the
  copied body in `#sourceLocation(file:line:)` back to the host was tried
  both ways — around the member and inside the braces, with
  `formatMode: .disabled` and dump-verified anchors — and the directive is
  accepted, remaps correctly, and changes nothing: it remaps regions that
  are never emitted. Don't retry from the macro side; the gate is the
  compiler's emission, not the mapping.
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

## `QueryCore`

### Live-wrapper interface parity

`Sources/CoreFlow/QueryCore.swift` defines a plain non-macro
`@propertyWrapper`, the way `Reflector` is a non-macro utility. `@Shell`
substitutes it for `@Query` as `@QueryCore var name: T`.

Verified directly against `_SwiftData_SwiftUI`, the real
`Query<Element, Result>` instance surface is exactly `wrappedValue`,
`fetchError`, and `modelContext`, with **no `projectedValue`**. `QueryCore`
carries those same three members and nothing else; `modelContext` is private and
there is no `$x` projection.

A bare `(wrappedValue:, fetchError:)` tuple was rejected. Copied body text needs
read-surface parity with the live wrapper: `items.isEmpty` and `ForEach(items)`
must still read the supplied array directly, while `_items.fetchError` keeps the
same spelling. A tuple field would force `.items.wrappedValue` on every copied
read.

### Memberwise-initializer behavior

`fetchError` defaults to `nil`, so `QueryCore(wrappedValue: [item])` works.
Because the wrapper has an initializer callable with `wrappedValue` alone,
Swift's synthesized memberwise initializer takes the *bare* fetched value for a
`@QueryCore` field. Tests therefore write
`Core(items: [item], title: "t")` with no `QueryCore` spelling. `QueryCoreTests`
lock both bare-value memberwise construction and explicit-wrapper seeding.

### Hosted environment behavior

`modelContext` is environment-fed like the live wrapper through a private
`@Environment(\.modelContext)` field. `QueryCore` is a `DynamicProperty`, so the
field installs when `Core` is hosted and follows SwiftUI's native mocking paths:
`.modelContainer` or `.environment`. It is never read unhosted and is not an
initializer parameter.

### Test access pattern

Normal tests use the bare-value memberwise initializer. When raw backing access
is genuinely required, a same-file extension can reach `_name`; see
`QueryCoreTests`' `FakeCore`. The `@Shell` section retains only the local
construction consequence and this pointer.

## Logged-property family

### Shared contract

`@TestState`, `@TestAction`, `@UnstructuredTask`, and `@TestFocusState` expose
live properties whose component-owned boundary events enter one ordered log.
They are per-property macros: each declaration opts in and hardcodes its own
name, with no type-level key-path selector. Scenarios assert the ordered
execution log, never an effect.

Only deterministic writes and calls log. Getter reads and system-owned focus
changes occur when SwiftUI's scheduler decides, so their counts vary by runtime
and device. One nondeterministic line poisons the all-or-nothing log diff; a test
that needs read evidence uses a predicate-based spy binding instead.

Invalid shapes throw one compile error from accessor expansion. Peer expansion
uses the validated shape or remains silent so the same error is not emitted
twice. Never skip malformed input that could compile as unmanaged state.

| Macro | Property shape | Storage | Init accessor | Payload | Projection |
|---|---|---|---|---|---|
| `@TestState` | stored `var`, any type | `State<T>` peer | yes | described new value | routed `Binding<T>` |
| `@TestAction` | stored closure `var` | closure peer | yes | arguments by arity | none |
| `@UnstructuredTask` | computed optional task slot | `State<TaskStorage<T>>` peer | no | `task` / `nil` | routed `Binding<T?>` |
| `@TestFocusState` | computed focus slot | `FocusState<T>` peer | no | described programmatic write | native `FocusState<T>.Binding` |

### Shared logging seam

`testLog` is an internal `@Entry`; its `ComparableLog` value is an always-equal
struct rather than a bare closure entry that would warn about invalidation.
`TestLog` is a `DynamicProperty` wrapping the hand-written environment read, and
its `wrappedValue` is the `@MainActor (String, String) -> Void` sink. Global-
actor function values are implicitly Sendable, so all events serialize on the
main actor.

Payloads are `String`, not `Any`: an `Any` containing a class can fail region
isolation inside a generated `@Sendable async` closure, where the caller cannot
repair it. `String(describing:)` freezes ordinary values at the event site;
macros use a stable symbolic payload when a description is nondeterministic.

Generated code stores `private let log_name = TestLog()` explicitly, never
`@Environment(\.testLog)` wrapper sugar. The sugar SILGen/IRGen-crashes swiftc
6.4 with signal 11 while emitting its synthesized getter. Hand-written identical
source compiles; generated `\.self` and `EnvironmentValues` variants also crash,
so the closure-valued entry is not the cause. The explicit field preserves
nested `DynamicProperty` installation, verified by the UI tests.

Outside hosting the environment entry returns its no-op default but SwiftUI
reports an uninstalled read. Unit tests therefore stop at generated surfaces;
the example app's hosted UI tests own logging and forwarding behavior.

## `@TestState`

- **`@TestState var count: Int = 0` is a drop-in `@State` that logs —
  accessor + peer, the property stays LIVE.** The accessor role rewrites
  the property itself: an init accessor (`@storageRestrictions(initializes:
  count_storage)`) funnels the inline default into the storage, `get`
  reads `count_storage.wrappedValue`, and the single logging point is the
  `nonmutating set`. Peers: `private let count_storage: State<Int>`
  (initialized via the init accessor), `private let log_count = TestLog()`,
  and `` `$count` `` — a `Binding` routed through
  the property itself, so direct writes and binding writes log through the
  same setter. Everything generated is `private` — `$name` included; only
  the host's own `body` wires it. Type from the annotation or the shared
  three-literal inference (`inferredLiteralType`).

Swift's synthesized memberwise initializer supplies both access roles. An
internal defaulted property remains a defaulted parameter across files
(`TestSupportTests`' probe hosts); a private defaulted property is excluded and
becomes the sealed source of truth generated by `@Shell` and used by scenarios.
The init accessor subsumes the storage peer, while `TestLog()` supplies its own
default, so neither peer becomes a parameter. Macro-generated dollar names are
legal through `names: prefixed($), prefixed(log_)[, suffixed(_storage)]`.

## `@TestAction`

- **`@TestAction var save: (Item) -> Void = { _ in }` — the property's own
  getter IS the logged action, no `$name`, no setter.** Accessor + peer:
  an init accessor funnels the inline default into a `save_storage` peer,
  and the getter returns a wrapper closure logging an arity-shaped payload
  — `""` for zero args, `String(describing:)` of bare `a0` for one, of a
  tuple beyond — then
  forwarding with `return`/`try`/`await` each added iff the declared type
  needs it. The getter extracts `log` (the resolved sink closure,
  `@MainActor` hence Sendable) and `storage` into locals first, so the wrapper captures
  two plain values and never `self` — deliberate: no view copy dragged
  into `async`/`@Sendable` action closures, and Environment resolution
  happens at the view copy's install either way (an env change re-renders
  `body`, minting a fresh wrapper — same net freshness as a self-capturing
  read). `var`, not `let` — the compiler refuses accessor expansion on
  `let` (dead ends below); a `let` closure is a thrown compile error like
  any other unspellable shape.

Synchronous wrappers and ordinary async wrappers call the sink directly; adding
`await` to the latter produces the verified unnecessary-await warning because
they inherit host isolation. Only a `@Sendable async` wrapper cannot inherit it,
so it awaits the log in order before forwarding. Never use a fire-and-forget
`Task`, which could reorder action events against synchronous state writes.

## Logged-property dead ends (interim)

Checkpoint 6 moves these complete dead ends to the top-level rejected-designs
section without changing their substance.

- **Dead ends worth remembering if anyone revisits an in-place rewrite:**
  the compiler hard-refuses accessor macros on `let` (`cannot expand
  accessor macro on variable declared with 'let'` — verified directly, no
  role gets around it); `@State` sugar on a generated storage peer breaks
  `@storageRestrictions(initializes:)` subsumption (the wrapper's own `_x`
  backing landed as an extra memberwise parameter — verified directly);
  and an init-accessor property's inline default runs at the top of EVERY
  init, so `let` storage peers double-initialize (verified directly).

## `@UnstructuredTask`

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
  initial value isn't configurable by design. `validated()` explicitly checks
  `binding.initializer == nil`; the initializer check is real, not delegated to
  the compiler, because a skipped declaration could remain plain, silently
  unmanaged stored state.
  The macro also generates a private `$name: Binding<T?>` whose getter and
  setter route through the logged property, so binding writes share its
  cancellation and logging behavior.
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
  wrong. Only the sugared `T?` counts: anything else — IUO (`T!`),
  long-form `Optional<T>`, a missing annotation, `let`, a written
  default — is a thrown compile error (family policy; the written-default
  case is the reason it can't be left to the compiler — see the
  `@TestFocusState` section). Both types public: generated code lands in
  the consumer's module.
- **Payload is `"task"`/`"nil"`, not `String(describing:)`.** A described
  `Task` isn't snapshot-stable, and one nondeterministic line poisons the
  all-or-nothing log diff — same criterion as the getters-don't-log rule.
- **Under `@Shell` it's deliberately NOT whitelisted**: it rides rule 2 as
  an unknown wrapper — the verbatim copy re-expands the macro on `Core`
  (locked by `UnstructuredTaskTests`), and the computed property stays out
  of the memberwise init on both types, so the twin cancels and logs
  identically with nothing to substitute.

## `@TestFocusState`

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
  non-single-stored-instance-var shape — now the family-wide policy (this
  macro set it; `@TestState`/`@TestAction`/`@UnstructuredTask` follow the
  same `validated` throw pattern), because a silent skip can COMPILE:
  `@TestFocusState var focus = false` skipped is a plain, unmanaged
  stored property that never logs, and the compiler accepts macro-added
  `get`/`set` accessors on an initialized `var` without complaint
  (verified directly — the "variable with accessors can't have an initial
  value" error does NOT fire for macro-added accessors on this toolchain,
  so "let the compiler catch it" cannot work; the same fact is why
  `@UnstructuredTask` refuses a written default itself). The accessor
  role throws, the peer role stays silent
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
- **Unhosted, reads return the wrapper's reset value and writes no-op**
  like the live wrapper's own — and the setter's sink call reaches only
  `\.testLog`'s no-op default, since the one installer is the
  `View.testLog(_:)` modifier: asserting focus intent through the log
  requires a hosted scenario with the sink installed, like every other
  logged event. Package tests stop at the lifecycle
  boundary — no unit test evaluates unhosted wrapper behavior; what's
  locked here is the expansion shape (`TestSupportSyntaxTests`) and the
  substitution + the non-private diagnostic (`ShellSyntaxTests`);
  read/write/projection parity holds by type identity (`name` reads the
  bare value on both sides, `$name` is the same nominal
  `FocusState<T>.Binding` on both). Live focus movement and logging are
  the example app's story.

## `@Capability`

### Contract and generated surface

This `member` macro generates a `Capability` typealias and a computed
`capability` property containing exactly the operations a consumer may use, not
the whole source object—Scott Wlaschin's capability-based design ("Designing
with capabilities", fsharpforfunandprofit.com/cap). Entry, collection, and
rendering all live in `Sources/CoreFlowMacros/CapabilityMacro.swift`.

Capability does not use `StoredProperty`: it collects computed properties and
methods, while that shared model describes stored declarations. This difference
also explains why Capability works on an extension as well as a struct, class,
or actor; extensions may declare computed members but never stored properties,
so the same attachment would give Flowable nothing to collect.

### Eligible members

| Declaration | Result |
|---|---|
| computed property with explicit result type | value of that type |
| instance method | closure with labels removed, effects retained, omitted return becoming `Void` |
| `private`/`fileprivate`, `static`/`class` | skipped |
| stored property, including observer-only storage | skipped |
| initializer or subscript | skipped |
| `mutating` method | skipped |

Computed properties need explicit types because the macro sees syntax, not type
information. Mutating methods are excluded because Swift cannot form the needed
closure reference: `error: cannot reference 'mutating' method as function
value` (verified directly).

### Shape and evaluation rules

Multiple members form a labeled tuple; one collapses to its bare type/value
because Swift has no one-tuples. Zero emits the package diagnostic—there is no
useful empty capability. `collectCapabilityMembers` walks
`decl.memberBlock.members`, appending eligible bindings and methods as visited;
the renderer maps that array unchanged, so tuple fields and values follow source
order.

The getter evaluates computed properties when building the capability, while
method closures remain connected to the source instance. Verified at runtime:
after incrementing the source, a cached capability's `doubled` stayed `0`; a
fresh `counter.capability.doubled` returned `2`. Re-read the property when current
computed values matter.

### Sendability

Generated closure fields deliberately omit `@Sendable` — verified directly,
both ways. Adding it unconditionally rejects non-Sendable captures: `error:
converting non-Sendable function value to '@Sendable () -> Void' may introduce
data races`. Omitting it
still permits cross-task/actor use when Swift 6 region checking proves the tuple
construction safe; that check happens where the capability value is built,
independent of the field's declared closure type. This is not an unconditional
Sendable guarantee.

### Generic-method limit and verification

Generic methods work when contextual inference specializes the reference
without exposing a placeholder in the tuple field type. A signature whose
emitted type text needs that placeholder outside its scope is an unguarded
limitation, not specially diagnosed.

`CapabilityTests` owns both expansion and compiled coverage, including
extension attachment, effects, one/many/zero shapes, access, and diagnostics.

## `#pick`

### Contract and overload model

`#pick(from: value, \.a, \.b)` is an expression macro. One `PickMacro`
implementation backs arity-generic overloads for one, two, and three sources;
each reads a flat argument list whose repeated, predeclared `from:` labels mark
source-pack boundaries. Implementation lives in `PickMacro.swift` and
`KeyPathPick.swift`.

### Labels, renaming, and order

The expansion constructs a labeled tuple in written order, but the parameter-
pack return type cannot carry element labels. Callers therefore read a multi-
pick result positionally (`.0`, `.1`), even though expansion output contains
labels.

An arbitrary argument label cannot rename one pack element: argument labels
match declared parameters, and a pack is one parameter. The `=>` operator
instead creates a real expression of the same KeyPath type; the macro reads its
rename syntax without evaluating it. `from:` is different because it is part of
the declared overload and separates source packs.

Each distinct source expression is bound once as `__v0`, `__v1`, … in order of
first appearance, even when reused across groups. Output fields follow the
written pick order, not the source type's declaration order.

### Toolchain and nesting limits

Bare tuple sources work because tuple KeyPaths are live on the pinned toolchain;
older Swift versions require verification. Tests also lock heterogeneous tuple
paths, including the ordinary
`WritableKeyPath<(a: Int, b: String), Int>` shape.

Two nested calls resolving to the same declared overload fail with `error:
recursive expansion of macro 'pick(from:_:)'`; split them into statements.
Different-arity nesting works. The recursion guard keys on resolved-overload
identity, not macro spelling or shared implementation type.

### Diagnostics and verification

Duplicate labels diagnose as `#pick: duplicate field label 'limit' — rename
this pick` with Fix-It `rename to "limit2"` (the concrete label varies). Parser
diagnostics also reject non-KeyPath picks and non-literal rename operands; keep
their exact source-tested spelling in `PickMacroTests`.

`PickMacroTests` owns expansion, ordering, renames, tuple sources, diagnostics,
and Fix-Its. `EndToEndTests` owns compiled overload resolution, positional
results, tuple KeyPaths, and nesting behavior.

## `Reflector`

### Contract and implementation

`Reflector` is ordinary runtime Swift, not a macro. The enum in
`Sources/CoreFlow/Reflector.swift` exposes one function,
`public static func fieldNames<T>(of: T.Type) -> [String]`, because field-name
reflection naturally complements Flowable's generated `InFlow`.

The caller supplies only `T.self`. The function allocates one uninitialized
`T`, reflects `p.pointee`, collects `children.compactMap(\.label)`, and
deallocates the pointer without initializing or deinitializing its pointee.

### Safety boundary

Current Mirror behavior obtains field labels from metadata, and Reflector never
requests a child's `.value`. This has been verified for value types containing
class references, closures, and arrays. The function still reflects storage
that was never initialized: treat it as an implementation-dependent runtime
technique, not a general Swift memory-safety guarantee.

The top-level value-type requirement is enforced at runtime with
`precondition(!(T.self is AnyClass), ...)`. Swift has no generic “not a class”
constraint, and a marker protocol cannot include tuples. The same language gap
allows a final class to conform to `View`; “views are structs” is convention,
not compiler enforcement.

A top-level class traps because Mirror attempts a `CustomReflectable` cast using
an invalid uninitialized reference. The guard concerns `T` itself, not its
fields: structs containing class, closure, or array fields succeeded in direct
verification under the implementation-dependent caveat above.

### Flowable relationship and access

`Reflector.fieldNames(of: Point.InFlow.self)` reports real names because
`InFlow` is labeled. An unlabeled tuple reports positional labels (`.0`, `.1`)
rather than failing; `InFlow` is the intended field-name target.

A top-level private or fileprivate Flowable type restricts its generated
members. In particular, `InFlow` on a private `Point` is accessible only inside
Point or its extensions, not generally from elsewhere in the file. Same-file
external access requires a non-private Point (or a reference inside Point/an
extension).

`ReflectorTests` owns runtime labels for structs, one-field values, labeled and
unlabeled tuples, and Flowable integration. Direct source inspection owns the
public signature; the top-level class and reference-containing-field behavior
come from the recorded direct probes.
