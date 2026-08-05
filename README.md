# CoreFlow

A small, growing collection of independent Swift macros, all shipped from one
library — a single dependency gets you every macro below:

```swift
// Package.swift
.package(url: "https://github.com/sisoje/swift-core-flow.git", from: "1.0.0"),

// target dependency
.product(name: "CoreFlow", package: "CoreFlow"),
```

Requires Swift 6.3+ (`swift-tools-version: 6.3`). Builds across the whole swift-syntax
6xx line. Run everything with `swift build && swift test`.

The conceptual model — nodes coupled by data, flow at creation, testing as
reading the execution log — is one article:
[SwiftUI Data Flow Masterclass](https://medium.com/@redhotbits/swiftui-data-flow-masterclass-099f0768f776), published on Medium and
taught macro-free; the macros mechanize its shell/core split. This README
is the per-macro reference.

## What's inside

| Concept | Form | Does |
|---|---|---|
| [`@Shell`](#shell) | member macro | generates a nested `Core` struct — the host's standalone twin: same body, every data boundary observable, directly constructible in tests (previews reach it through a hand-written wrapper view — `#Preview`'s own expansion can't name macro-generated code) |
| [`@Flowable`](#flowable) | member macro | writes a memberwise `init` at the type's own access level, plus a `makeFlow(_:)` factory taking the same properties as one unlabeled tuple and an `InFlow` typealias naming their labeled shape |
| [`@TestState`](#teststate-and-testaction) | accessor + peer macro | a drop-in `@State` that logs every mutation — each write reaches the injected sink the moment it happens, binding writes included |
| [`@TestAction`](#teststate-and-testaction) | accessor + peer macro | an action closure that logs every call — reading the property IS the logged action; each call logs its payload to the injected sink, then forwards |
| [`@TestFocusState`](#testfocusstate) | accessor + peer macro | a drop-in `@FocusState` that logs every programmatic write — a real `FocusState` underneath, so focus genuinely moves when hosted; `$name` is the real `FocusState<T>.Binding` |
| [`@UnstructuredTask`](#unstructuredtask) | accessor + peer macro | a view-owned slot for a cancellable unstructured `Task` — assigning cancels the previous task, view teardown cancels the live one, and every mutation logs like `@TestState` |
| [`@QueryCore`](#querycore) | property wrapper | `@Query`'s drop-in stand-in on `Core` — the fetched result as a bare init parameter (`Core(items: [item], …)`), same read surface as the live wrapper, no SwiftData stack |
| [`@TestLog`](#the-testlog-seam) | property wrapper | reads the installed sink — `@TestLog private var log` self-initializes and `log(name, value)` is a direct call (verified); the macros generate the same thing as an explicit field, `private let log_x = TestLog()` |
| [`View.testLog(_:)`](#the-testlog-seam) | View modifier | installs the one logging sink, once, on the root view; without it the log is a no-op, so hosts behave normally anywhere else |
| [`@Capability`](#capability) | member macro | bundles every eligible computed property/method into a `Capability` tuple + computed property — works on an extension |
| [`#pick`](#pick-tuplepicker) | expression macro | projects one or more fields — via KeyPath — from one or more sources into a single tuple |
| [`Reflector`](#reflector) | runtime utility | lists a value type's field names off its type alone, no instance needed — pairs with `@Flowable`'s `InFlow` |

---

## Shell

The names are the pattern: **functional core, imperative shell**
(Bernhardt, Wlaschin, Seemann — see [References](#references)). The host is
the shell — its wrappers are where the runtime does I/O. `Core` is the
extracted core: identical logic with every data boundary made observable —
its own state logged, external storage mocked through bindings, fetched
data as plain values, effects as injected closures — constructible and
assertable anywhere. Mocking the external sources as data also severs
their event channels: no storage change or fetch notification can trigger
a re-render mid-test. UI-runtime wrappers that aren't data (gestures,
view identity) have no boundary form and ride along as-is
(see the [wrapper mapping reference](#wrapper-mapping-reference)).

Concretely: a `member` macro generating a nested `Core` struct —
always internal, regardless of the attached type's own access level —
the host's standalone twin: every stored property
the host declares, in exactly two kinds — *mapped* wrappers substituted with a
mockable stand-in (the whitelist in the
[wrapper mapping reference](#wrapper-mapping-reference), the only wrappers
this package really knows), and everything else copied
verbatim. Plus a
verbatim copy of every non-stored member — `body`, helpers, methods, static
members, nested types.
Initializers are the one member kind not copied:
`Core` is constructed through Swift's synthesized memberwise init, and a
copied init would suppress it. Members declared in a separate extension of
the host aren't seen (a macro only receives the attached declaration's own
syntax).

```swift
@Shell
struct Card: View {
    @Query private var items: [Item]
    @State private var isExpanded = false
    let title: String

    var body: some View { ... }   // ordinary SwiftUI, written once

    // generates:
    // struct Core: View {
    //     @QueryCore var items: [Item]
    //     @TestState private var isExpanded = false
    //     let title: String
    //     var body: some View { ... }   <- the same text, copied
    // }
}

// #Preview can't name macro-generated code like Core — hence the wrapper;
// its construction is also a unit test's entire setup:
struct CardScenario: View {
    var body: some View {
        Card.Core(items: [item], title: "t")
    }
}

#Preview { CardScenario() }
```

Three words, fixed meanings, used throughout: the **host** (`Card`) is the
production shell; **`Core`** is its generated twin; a **scenario**
(`CardScenario`) is the hand-written view that stages a `Core` with
mocks — what a preview shows and a UI test launches. And driving one from
the UI-testing bundle is not an end-to-end test wearing a costume:
**a UI test driving a scenario is a test of an actual unit — the `Core`** —
real taps, real focus, real gestures against one component whose every
boundary event lands in the log (the example app does exactly this: its
`SCENARIO` launch variable selects the scenario, the XCUITest asserts the
log).

### Wrapper mapping reference

Two rules. **Substituted** — the mapping whitelist, the only wrapper kinds
this package really knows, all required private on the host. `@State` is
the view's **own** state → [`@TestState`](#teststate-and-testaction), the
host's line with just the wrapper renamed: still private, sealed out of
the memberwise init, starting at the host's inline default (required — a
defaultless `@State` is a compile error; nothing to copy is diagnosed,
never silently patched), logging every mutation. Ownership is unchanged
on purpose: an internal source of truth is never a caller's, and moving
it up to observe it would falsify the component's data flow — the write
site emits evidence instead. `@AppStorage`/`@SceneStorage` are
**external** storage, a dependency → `@Binding`, the mock vehicle: a
test supplies the storage and captures every write (keys dropped — a test
twin doesn't persist). `@Query` → `@QueryCore`: fetched data as a
bare-value init parameter (reading a fetched array shouldn't require
standing up an entire SwiftData stack).
`@FocusState` is the view's own focus →
[`@TestFocusState`](#testfocusstate), the same rename treatment as
`@State` — not a mock (none is possible: `FocusState<T>.Binding` has no
public initializer, and focus writes no-op outside a live view) but a live
instrument: a real `FocusState` underneath, every programmatic write
logged.
Exactly the wrappers where the substitution buys something real — a log, a
mock vehicle, a bare value — and nothing else qualifies
(`@AccessibilityFocusState`, `@FocusState`'s interface-exact clone, has no
substitute macro yet and rides the verbatim rule).
**Copied verbatim** — everything else, wrapper or not: the host's own
declaration as written. A plain field keeps its `let`/`var` and default (a
defaulted `let` is a constant on `Core` too — no memberwise parameter,
same as on the host; a *plain* private field is a compile error instead —
pure data flow has no room for it). A wrapper — `@Binding`,
`@Environment`, `@GestureState`, `@Namespace`, `@ScaledMetric`,
`@Bindable`, `@StateObject`, your own custom one, even a qualified
spelling (`@MyModule.Tracked`) no wrapper-name check recognizes — rides
onto `Core` byte-for-byte, attribute arguments and default included. Both
flavors keep `private` and erase `public`. Private
verbatim copies are sealed — no init parameter, no reads — they just
behave.

The split is principled. Whitelisted wrappers hold *data* — a value, a
fetched array — so they can be owned-and-logged, mocked, or handed in at
the boundary. Most of the rest is Apple's
UI-runtime machinery: `@GestureState` (gesture lifecycle), `@Namespace`
(view identity), `@ScaledMetric` (display metrics),
`@Environment` (the tree's value propagation). No caller can supply a live
gesture, so no substitution is attempted: machinery stays verbatim on
`Core` — live when hosted, inert defaults otherwise.

| Shell | Core |
|---|---|
| `@State` | `@TestState` |
| `@FocusState` | `@TestFocusState` |
| `@AppStorage` / `@SceneStorage` | `@Binding` |
| `@Query` | `@QueryCore` |

> **`@StateObject` and `@ObservedObject` are deliberately unmapped.** They're
> Combine-era `ObservableObject` wrappers — MVVM-shaped state, exactly what
> this package's plain-data model exists to avoid — so they get no mocking
> stand-in and never will. Like any unknown wrapper they're copied onto
> `Core` verbatim and left alone; if you want testable state, model it with
> the mapped wrappers instead. These are classes: reference-type state
> containers bolted onto a value-type dataflow, opaque to SwiftUI's
> dependency graph and to any snapshot of plain data — they clog the data
> flow. The full argument: the anti-MVVM entries in
> [References](#references).

### Mocking the bindings

`Binding` parameters — genuine host `@Binding`s and the
`@AppStorage`/`@SceneStorage` substitutions alike — are backed at the use
site, deliberately not generated (`@State` substitutions need nothing:
they own their storage and log every mutation): `.constant`, a
`Binding(get:set:)` capturing writes into a local, or an `@Observable`
model whose `Bindable(model).x` projection mints a real write-through
binding in plain code, no view needed:

```swift
var writes: [Bool] = []
let core = Toggler.Core(          // the host declares `@Binding var isOn: Bool`
    isOn: Binding(get: { false }, set: { writes.append($0) }))
core.isOn = true                  // the copied body's writes land the same way
```

(Generating a binding-wiring model class was considered and rejected — the
few lines it would save belong at the use site, shaped by the test.)

One testing gotcha: `@MainActor` is required on any test suite touching a
`View`-conforming type's members — `Core` included. `View` conformance
implicitly infers `@MainActor` isolation for the whole type, so a
nonisolated test function crosses that boundary at runtime and traps under
Swift 6 strict concurrency, even just reading a computed property.

### QueryCore

A real, one-to-one drop-in for the live `@Query`.
Verified directly against the `_SwiftData_SwiftUI` interface: `Query`'s
instance surface is exactly `wrappedValue`, `fetchError`, and
`modelContext`, with **no `projectedValue`** — so `QueryCore` carries the
same three (its `modelContext` private) and nothing else. That read-surface match is what lets the
copied `body` compile on `Core`: the host's body text was written against
the live wrapper (`items.isEmpty`, `ForEach(items)`), and on `Core` the
same text still works because `core.items` reads the mock's array
directly — `_items.fetchError` spells the same on
both sides too. `modelContext` is environment-fed like the live
wrapper's (a private `@Environment` field — `QueryCore` is a
`DynamicProperty`, so it installs when `Core` is hosted, mocked via
`.modelContainer`/`.environment`, and is never read unhosted);
`fetchError` defaults to `nil`,
which makes `QueryCore`'s init callable with the wrapped value alone — so
`Core`'s synthesized memberwise init takes the *bare* fetched value, and a
test writes `Core(items: [item], title: "t")` with no `QueryCore` spelling
at all.

### One verbatim rule, no special cases

Whatever behavior lives in an unmapped wrapper's own attribute arguments —
a `@GestureState(reset:)` closure, an `@Environment` key path, a
`@ScaledMetric(relativeTo:)` — rides onto `Core` byte-for-byte with
nothing to reconstruct, proved live by a UI test (`TrickyDragCardUITests`
in `CoreFlowExample`: the custom reset closure fires on `Core`'s copy
exactly as on the host). A private copy is self-initializing (the host compiled
without an init assigning it), so it drops out of `Core`'s memberwise init
and produces its value live instead: an `@Environment` copy reads the *real* environment
reactively when `Core` is hosted (mock it there via `.environment(...)`,
the wrapper's own native story) and the default `EnvironmentValues`
outside a live view; a `@GestureState` copy starts a fresh gesture at its
declared default.

### Why a nominal struct, not a tuple

Tuples can't conform to protocols — verified directly against the real compiler:

```
type '(x: Int, y: String)' cannot conform to 'Equatable'
only concrete types such as structs, enums and classes can conform to protocols
```

So a tuple snapshot can never be `Equatable`, `Codable`, or conform to a shared
"any stateless snapshot" protocol for generic code to work with — and it can't
carry copied members or host live. `Core` is a
real nominal struct capturing the same data, so it can — for free, the moment it's
declared as a real `struct`.

### Why `Core` is always internal, with no init of its own

`Core` is a purely internal testing/preview seam — not part of the attached
type's public API, even when that type itself is `public`: consumers of a
public host never need the twin, only the module's own tests do (reachable
from the same module, or a `@testable import`). The struct is always
internal, never mirroring the attached type's access level; `@State`
substitutions stay private (the view's own source of truth), the other
substitutions are internal, verbatim copies keep `private` if the host
declared it (`public` is erased).

Internal also means **release builds ship no `Core` at all** — verified
directly against a release binary (`-O`, whole-module optimization, the
default for SPM and Xcode alike): an internal type nothing reaches is
eliminated by the *compiler* — code, metadata, and its `View` conformance
record, zero symbols in the binary — while the host beside it keeps every
symbol; the same source in a debug build carries the full `Core`. Tests and
previews run in debug, where the twin is fully present, so no `#if DEBUG`
is needed anywhere: release pays zero bytes for `Core`.

No init is generated or copied either. Swift's own memberwise-init synthesis
already handles every field-specific behavior — verified directly: a
property-wrapper field with no
`init(wrappedValue:)` (`@Binding`) synthesizes a parameter of the *wrapper's*
type, one that does (`@QueryCore`, `@Bindable`) synthesizes a parameter of
the *wrapped* type, and `@ViewBuilder` directly on a stored `let` synthesizes
a builder-closure parameter even for a value-typed field (see below).

**The mapped source-of-truth wrappers must be private — enforced with a
diagnostic, not accommodated.** They're a view's own source of truth, never
something a caller supplies (`@Binding` is for that); declaring one
non-private is a compile error, so every renderer downstream can assume the
substituted set is always private, with no "what if it's also public" case
to reason about. Unknown wrappers carry no privacy rule — private or not,
their declaration is copied verbatim, and a non-private one stays a
memberwise-init parameter like any other non-private field.

### Notes on the rows

- **`@Binding` lands on the same shape `@AppStorage`/`@SceneStorage` are
  substituted into** — its verbatim copy already *is* `@Binding var name: T`,
  the form the whitelist substitutes those wrappers into, so `Core` treats
  caller bindings and substituted storage identically. The payoff: `core.name`
  reads the wrapped value directly, no `.wrappedValue` unwrap — and
  `core.name = newValue` writes through to whatever storage the original
  binding pointed at.
- **`@ViewBuilder` rides the verbatim rule like everything else, on both
  its forms.** The stored closure (`content: () -> Content`) keeps real
  builder syntax at `Core`'s own init call site; the stored value
  (`let footer: Content`) keeps the attribute too, so `Core`'s synthesized
  init takes that parameter as a builder closure rather than a bare value
  (verified directly) — the host's own call shape, and matching it is the
  point of a verbatim copy. A `@ViewBuilder var` is a compile error
  (`viewBuilderMustBeLet`): builder content is caller-supplied through the
  generated init and never reassigned. `@ViewBuilder` is *not*
  a `@propertyWrapper` — it's a result-builder attribute, legal directly on
  stored properties (verified directly).

### Automatic `View`/`ViewModifier` detection

When the attached type's own inheritance clause spells `View` or
`ViewModifier`, `Core` is additionally declared to conform to the same
protocol — satisfied by the copied `body`/`body(content:)`. For
`ViewModifier`, the copied `body(content:)`'s `Content` resolves to `Core`'s
*own* `ViewModifier.Content` — a different concrete type from the host's
(`typealias Content = _ViewModifier_Content<Self>` is keyed on the conforming
type itself, verified directly) — which is fine: each type satisfies the
protocol independently.

**This detection is syntactic, not semantic.** A macro never gets a type
checker, so it can only read the literal inheritance clause written on the
attached declaration itself — conformance added in a separate extension
elsewhere, via a typealias or protocol composition, or spelled with a
qualification (`SwiftUI.View`), is invisible to it. Only a bare `View`/
`ViewModifier` identifier directly on the attached type is recognized.

### How a Core relates to its host

The host is a completely ordinary SwiftUI view — its hand-written `body`
reads caller-supplied values and its own sources of truth directly. `Core` is
the same code with the runtime unplugged:

```mermaid
flowchart TD
    subgraph Outside["from outside — caller-supplied"]
        Bind["@Binding<br/>e.g. isOn"]
        Plain["plain fields<br/>e.g. title"]
    end

    subgraph SOT["runtime-supplied"]
        State["@State / @AppStorage"]
        Query["@Query"]
        Env["@Environment"]
    end

    Outside --> Card
    SOT --> Card

    subgraph Card["Card — stateful, live, ordinary SwiftUI"]
        CardBody["body + helpers<br/>hand-written, reads the real wrappers"]
    end

    subgraph SN["Card.Core — its standalone twin"]
        Fields["substituted fields<br/>@TestState/@TestFocusState (log) · @Binding (writes through) · @QueryCore (bare value)"]
        SNBody["body + helpers<br/>the same text, compiler-copied"]
        Fields --> SNBody
    end

    CardBody -. "@Shell copies every<br/>non-stored member" .-> SNBody
    Test(["unit test / wrapper view"]) -. "construct Core directly —<br/>no live view, no environment, no ModelContext" .-> Fields
```

- **`CardBody -.-> SNBody`** (dotted, generated) — the copy: one source
  text, two types. The live view runs it against the real wrappers; `Core`
  compiles the identical text against the substituted fields. Drift is
  impossible.
- **`Test -.-> Fields`** (dotted) — the payoff: construct a `Core` directly
  with mocks — in a unit test, or in a hand-written wrapper view that a
  preview shows (see below) — and assert on its fields, call its helpers,
  or render its body, no live rendering pipeline required.

### Previews: one hand-written wrapper away

`#Preview { Card() }` works — the host's body is ordinary hand-written
source. `#Preview { Card.Core(…) }` does NOT compile, and no macro package
can make it: `#Preview` is itself a macro expansion, and one expansion
cannot reference names another expansion generated — a Swift-level rule
(verified directly, five ways). A macro-generated name also fails in a
file-scope TYPE position (`func f() -> Card.Core` at file scope); reference
it in expressions or behind `some View`.

The fix costs one ordinary type — the scenario from the chapter intro:
`Card.Core(…)` sits in expression position inside a hand-written view, and
`#Preview { CardScenario() }` names only ordinary types. The example app's
scenarios double as exactly this — every one is a hand-written stage that
a preview (and a UI test) can name.

---

## TestState and TestAction

**Why this exists.** How would Apple test `Button`? Its entire contract is
**"a physical tap calls the action closure"** — there is nothing inside to
inspect. And that contract can silently rot: change the component's
internals so the tap no longer reaches the action, and **no compiler, no
type check, no screenshot — and no unit test — will ever notice**: the
button still renders, still animates, still looks tappable, and a unit
test never taps anything. Exactly one test catches it: hand the button an
action that *logs*, tap it for real, check the log. Literally:

```swift
struct ButtonTestHost: View {
    @TestAction private var action: () -> Void = {}   // inert — reading it IS the logged action

    var body: some View {
        Button("Save", action: action)
    }
}

ButtonTestHost()
    .testLog { name, _ in
        // append name to the history
    }

// UI test: tap "Save", then inspect the history: ["action"]
```

**The tap called the action — the contract is proven, and the effect was
never executed.** Break the wiring inside the component, and this is the
test that fails.

Every `Core` has `Button`'s shape (see [`@Shell`](#shell)): its whole
behavior is state writes and calls to injected closures. So every `Core`
tests the same way — and mostly wires itself: the substituted `@TestState`
fields already own and log their state, so a *scenario* like the host
above adds only what the host takes from callers — `@TestAction` closures,
data arguments, backings for genuine `@Binding`s. Everything
logs to the injected sink **at the write site** — not via a view-layer
observer replaying history. **No effect is ever executed; the log IS the
behavior.**

- **`@TestState var count: Int = 0` is a drop-in `@State` that logs every
  mutation.** The property stays LIVE (real `State` storage behind a
  generated accessor); the single logging point is the setter, and the
  generated `$count` `Binding` routes through the property itself — direct
  writes and binding writes log identically. Works on a `var` of ANY type, closures included (a `var`
  closure means someone wants to mutate the closure itself, and the binding
  is exactly that). Type from the annotation or a bare `Bool`/`Int`/`String`
  literal default. Everything generated is private — only the host's own
  `body` wires `$count`.
- **`@TestAction var save: (Item) -> Void = { _ in }` — reading the property
  IS the logged action.** The getter returns the stored closure wrapped with
  logging: each call logs an arity-shaped payload (`""` for zero arguments,
  the described bare argument for one, a described tuple beyond), then
  forwards — `return`/`try`/`await` carried through exactly as the declared
  type needs. The wrapper captures two locals, never the view — no `self`
  dragged into `async`/`@Sendable` action closures. Closures only, `var`
  only, and no setter: an action is wired, not mutated.
### The testLog seam

- **One seam, two ends.** `testLog { name, value in … }` installs the
  sink; the macros read it through `TestLog`, a `DynamicProperty` and real
  `@propertyWrapper`. Hand-written code may use either spelling —
  `@TestLog var log: …` sugar or a constructed field — but generated code
  gets only the explicit field (`private let log_x = TestLog()`):
  macro-generated wrapper *sugar* crashes swiftc (verified directly;
  hand-written identical sugar compiles fine), so the constructed-value
  form is the one the macros can emit — and why the table spells the type
  bare. Bad shapes throw from expansion — a compile error at the
  attribute naming what's wrong (missing type/default, `let`, non-closure
  on `@TestAction`) — the family-wide policy: a silent skip can compile
  as a plain, unmanaged stored property that never logs.
- **The sink is `@MainActor (String, String) -> Void`** — every log lands
  serialized on the main actor whatever context the logged action runs in —
  and the default is a no-op, so hosts behave normally wherever no sink is
  installed.
- **Payloads are `String`, described at the call site.** `String(describing:)`
  freezes the value the moment it happens — a logged class reference can't
  mutate before a sink formats it — and only the Sendable result crosses
  into a `@Sendable async` action wrapper, which `await`s the log IN ORDER
  before forwarding: deliberately no fire-and-forget `Task`, which could
  reorder log lines against synchronous state writes.
- **Effects log; getters don't.** Setters and action calls fire on the
  component's own timing — **deterministic, so a test asserts the exact
  sequence with one equality check**. Getter reads fire on SwiftUI's render
  schedule — nondeterministic counts would poison an exact-sequence
  assertion. A test that needs "was this read?" uses a use-site spy binding
  instead.

Demonstrated live in the example app (`CoreFlowExample` — deliberately
collapsed to a `SPEC.md` its sources regenerate from): the
app appends every `(name, value)` into plain `@State` and exposes the
log on an accessibility element (names JSON in `label`, values JSON in
`value`); each XCUITest drives one scenario, waits for the label to equal the
expected name sequence, then asserts the decoded values — down to
`TextField` writing its binding twice per keystroke, real behavior pinned
as-is.

---

## UnstructuredTask

A view-owned slot for a cancellable unstructured `Task` — with
`@TestState`'s logging. An unstructured `Task { }` has no lifecycle of its
own: hold one in plain `@State` and nothing cancels it when a new one
replaces it or the view leaves the graph. `@UnstructuredTask` adds exactly
those two structure guarantees, as a per-property macro in the `@TestState`
family:

```swift
struct DownloadButton: View {
    @UnstructuredTask private var download: Task<Data, Error>?

    var body: some View {
        Button("Download") {
            download = Task { … }   // cancels any previous download, logs ("download", "task")
        }
    }
}
```

- **Assigning cancels the previous task; teardown cancels the live one.**
  The property reads/writes a `TaskStorage` box held in a generated `State`
  field — a *class* in `State`, not `State<Task?>`, because the lifecycle is
  the point: the box's `willSet` cancels on replacement, its `deinit` cancels
  when SwiftUI releases the storage, a hook a value in `State` doesn't have.
  The `willSet` is equality-guarded (`Task`'s `Equatable` is identity), so
  writing the task it already holds back into it — a binding round-trip, a
  defensive `x = x` — is not a cancel. The box is `@Observable`, so a `body`
  reading the property re-renders when the task changes.
- **The task always starts `nil`.** The property becomes *computed* over a
  self-initialized storage peer: a written default is a compile error
  thrown by the macro itself, and the property is never a memberwise-init
  parameter, whatever its access level.
- **Every mutation logs the property's actual name**, through the same
  `\.testLog` seam as [`@TestState`](#teststate-and-testaction), at the write
  site — `("download", "task")` on assignment, `("download", "nil")` on
  clearing. The payload is deterministic on purpose: a described `Task` isn't
  snapshot-stable, and one nondeterministic line poisons an exact-sequence
  assertion. In production no sink is installed and the log is a no-op — the
  wrapper is not test-only.
- **The generated `$download` binding routes through the property** — a
  binding write cancels and logs exactly like a direct write. Private, like
  every generated member; the host's own `body` wires it
  (`ChildView(task: $download)`).
- **Required shape:** a stored `var` with an optional-*sugared* type
  annotation (`Task<Success, Failure>?` — or a typealias of a task type: the
  storage's element is the annotation minus its `?`, constrained to the
  `CancellableTask` protocol rather than parsed into `Task`'s generic
  arguments; `Task<…>!` and long-form `Optional<Task<…>>` don't count).
  Anything else is a compile error at the attribute, thrown by the macro
  itself — same policy as the whole family.
- **Under [`@Shell`](#shell)** it rides the verbatim-copy rule like any
  unrecognized wrapper: `Core` gets the same declaration, the macro
  re-expands there, and the computed property stays out of the memberwise
  init — the twin cancels and logs identically.

## TestFocusState

A drop-in `@FocusState` that logs every programmatic write — and what
[`@Shell`](#shell) substitutes for `@FocusState` on `Core`, the same
rename treatment as `@State → @TestState`:

```swift
struct LoginScenario: View {
    @TestFocusState private var focus: Field?

    var body: some View {
        TextField("email", text: $email)
            .focused($focus, equals: .email)   // $focus IS FocusState<Field?>.Binding
        Button("next") { focus = .password }   // logs ("focus", "Optional(MyApp.Field.password)")
                                               // — String(describing:) qualifies enum cases
    }
}
```

- **A real `FocusState` underneath.** The property becomes computed over a
  self-initialized `FocusState<T>` peer, so hosted behavior is the live
  wrapper's own — focus genuinely moves — and the setter logs each
  programmatic write the moment it happens. Like `@FocusState`, there is
  no inline default (focus starts at the wrapper's reset value —
  `false`/`nil`) and the property is never a memberwise-init parameter,
  whatever its access level.
- **The property logs, the projection wires.** `$name` forwards the real
  `FocusState<T>.Binding` — the exact nominal type `.focused(_:equals:)`
  demands, and one with no public initializer to wrap — so writes through
  the binding (the *system* moving focus: a tap, keyboard dismissal)
  deliberately don't log. Scheduler-owned timing has no place in a
  snapshot log — the same criterion that keeps getter reads out of it.
  Programmatic focus moves are the component's own decisions, and those
  all log.
- **Unhosted** (a directly constructed `Core`), reads return the reset
  value and writes no-op, exactly like the live wrapper — and the setter's
  sink call reaches only the no-op default, since `View.testLog(_:)` is
  the one installer: asserting focus intent through the log needs a hosted
  scenario with the sink installed, like every other logged event.
- Required shape: a stored instance `var` with a type annotation (`Bool`
  or an optional, the values `@FocusState` itself accepts) and no initial
  value. Anything else is a compile error at the attribute, thrown by the
  macro itself — never a silent skip: a skipped `@TestFocusState var focus
  = false` would compile as a plain, unmanaged stored property that never
  logs. (A well-shaped property with a non-`Bool`, non-optional annotation
  passes the macro and fails on the generated `FocusState` peer instead,
  in the compiler's own words — same as the live wrapper.)

---

## Flowable

A `member` macro that writes a memberwise `init` for the type it's attached to, **at
the type's own access level**. It fills the initializers Swift won't synthesize: the
`public init` a public struct needs, and *any* init for a `class` or `actor` —
including an `@Observable final class`. Alongside the init, it also declares
`makeFlow(_:)` — a factory building `Self` from the same properties bundled
as one unlabeled tuple — and `InFlow`, the labeled tuple typealias naming
that shape. See [below](#the-makeflow_-factory) and
[below that](#the-inflow-typealias).

Independent of [`@Shell`](#shell) — attach either or both. `Core`
deliberately carries no `@Flowable`: Swift's synthesized memberwise init
reproduces the same field behaviors, and nothing round-trips a `Core` back
into itself.

See the [diagram below](#how-makeflow-and-inflow-relate) for how the whole
shape fits together.

```swift
@Flowable
public struct User {
    public let id: UUID
    public var isActive = false
}
// generates:
// public init(id: UUID, isActive: Bool = false) {
//     self.id = id
//     self.isActive = isActive
// }
// public static func makeFlow(_ flow: (UUID, Bool)) -> Self {
//     Self(id: flow.0, isActive: flow.1)
// }
// public typealias InFlow = (id: UUID, isActive: Bool)
```

Works the same on a `class` or `actor`:

```swift
@Flowable
@Observable final class Counter {
    var count = 0
}
// init(count: Int = 0) { self.count = count }
// static func makeFlow(_ flow: Int) -> Self { Self(count: flow) }   // one property → bare type, not a 1-tuple
```

### What it does

- **Mirrors the access level** — `public struct` → `public init`, an internal type →
  unmodified `init`, and so on.
- **`var` defaults carry through** — `var x: Int = 0` → parameter `x: Int = 0`. An
  optional `var` is implicitly nil-initialized, so `var name: String?` → parameter
  `name: String? = nil`, just like Swift's own memberwise init.
- **Function-typed properties get `@escaping`**, attributed types included
  (`@MainActor () -> Void`, `@Sendable (Int) -> Void`). Optional closures
  (`(() -> Void)?`) pass through as-is — they're already escaping.
- **Skips** computed properties and `static`/`class` members; keeps stored properties
  that have only `willSet`/`didSet` observers.

### SwiftUI

- **`private` properties are excluded** from the init. The source-of-truth
  set (`@State`/`@FocusState`/`@AppStorage`/`@SceneStorage`/`@Query`) is *required*
  private; the other view-owned wrappers (`@Environment`, …) are private by
  convention — either way they fall out automatically.
- **`@Binding`** is threaded in as a projected `Binding<T>` parameter, assigned to the
  backing storage (`self._x = x`).
- **`@ViewBuilder`** carries onto the parameter so callers get trailing-closure syntax.
  A stored closure (`let content: () -> Content`) becomes `@ViewBuilder content: @escaping () -> Content`;
  a stored value (`let footer: Content`) becomes `@ViewBuilder footer: () -> Content` and the
  init calls it (`self.footer = footer()`). A `let` in both forms — a
  `@ViewBuilder var` is a compile error (`viewBuilderMustBeLet`): builder
  content is caller-supplied through the init and never reassigned.

```swift
@Flowable
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme: ColorScheme   // excluded (private)
    @State private var expanded = false              // excluded (private)
    @Binding var isOn: Bool
    let title: String
    @ViewBuilder let footer: Content

    var body: some View { /* ... */ }
}
// init(isOn: Binding<Bool>, title: String, @ViewBuilder footer: () -> Content)
```

### Design: for pure data

- **No real type inference — except three unambiguous literal kinds.** It's
  syntax-only: a property needing an explicit type must have one, *unless* its
  inline default is a bare `Bool`/`Int`/`String` literal (`var isOn = false`,
  `var count = 0`, `var label = "x"`) — those three are inferred straight off
  the literal's own syntax, no type checker involved. Anything else uninferable
  (a call, an identifier, `nil`, a collection literal, …) still needs an
  explicit annotation.
- **No stored `let` constants.** A constant isn't per-instance data — use `static let`.
  The macro doesn't special-case an instance `let`: `let version = 1` generates
  `self.version = version` (a `let`-reassignment error) — the type gets inferred as
  `Int` just fine (see above), it just doesn't help; either way it won't compile.
- **`private` marks a source of truth — nothing else.** Data flows in
  through the non-private properties; state lives in the private wrapped
  ones. Enforced in both directions: a source-of-truth wrapper declared
  non-private is a compile error (a caller can't supply a source of truth —
  `@Binding` is for that), and a private property with *no* wrapper
  (`private var cache = 0`) is a compile error too — opaque state that
  neither flows in nor is runtime-managed sits outside the data flow
  entirely. Same for caller-supplied kinds: `@Binding`/`@ViewBuilder`
  declared private are unreachable and rejected outright.

### The makeFlow(_:) factory

Alongside the init, `@Flowable` declares `makeFlow(_:)` — a static factory
building `Self` from the same properties bundled into one **unlabeled**
tuple parameter, spelled inline in the signature, forwarded field by field
into the init:

```swift
@Flowable
public struct User {
    public let id: UUID
    public let name: String
}
// public static func makeFlow(_ flow: (UUID, String)) -> Self {
//     Self(id: flow.0, name: flow.1)
// }

let user = User.makeFlow((id: someID, name: "Ada"))

// Any structurally-compatible tuple works, not just one built with these
// field names — the parameter is unlabeled:
let differentlyLabeled = (uuid: someID, label: "Ada")
let user2 = User.makeFlow(differentlyLabeled)
```

The parameter is built independently of the init, so it diverges from it in
a few ways:

- **Unlabeled** — `(UUID, String)`, not `(id: UUID, name: String)` — deliberately,
  so any structurally-compatible tuple converts into it, not just one built with
  these exact field names. Verified directly: a tuple
  *value* already bound with different labels (`let t = (xxx: 1, yyy: 2)`) fails
  to convert into a *labeled* tuple type of the same shape (`error: cannot
  convert value of type '(xxx: Int, yyy: Int)' to expected argument type '(x:
  Int, y: Int)'`), but succeeds once the target is unlabeled — Swift only
  enforces label agreement between two *labeled* tuple types. A labeled tuple
  *literal* (`(id: someID, name: "Ada")`, as above) converts into an unlabeled
  target either way, so you can still write field names for your own
  readability at the call site — only a pre-existing,
  differently-labeled variable needed the loosening. The real cost: with no
  labels, the compiler no longer catches two same-typed fields passed in the
  wrong order.
- **Spelled inline — deliberately no typealias naming the unlabeled tuple.**
  A second name for the shape earns nothing: [`InFlow`](#the-inflow-typealias)
  feeds the parameter with no conversion and is the better spelling for
  storing and diffing, and generic code couldn't constrain on a generated
  member typealias anyway (no protocol declares one — see
  [below](#deliberately-no-protocol-naming-the-shape)).
- **No per-field defaults.** Tuple element types can't carry `= default` — so an
  inline `var` default, and an optional `var`'s implicit `nil`, are both dropped,
  unlike the init right above it.
- **One property collapses the parameter to the bare field type** — Swift has no
  1-tuples (`(Int)` as a type is plain `Int` regardless of labels) — and `flow`
  is then the value directly, no positional index: `makeFlow(_ flow: Int)`,
  `Self(count: flow)`. Zero properties → no factory at all: nothing to build
  from, and the init already covers the zero-property case on its own
  (`init() {}`).
- **Never `@escaping` inside the tuple**, even on function-typed fields — a
  closure nested inside a tuple type is already escaping; writing the attribute
  there is a compile error. The single-field collapse is the one case that
  *does* need it (the closure becomes a direct function parameter), and the
  factory spells it exactly there.
- **`@ViewBuilder` fields ride as plain values.** A stored-value field
  (`@ViewBuilder let footer: Content`) keeps its own type in the tuple
  (`Content`, not `() -> Content`). The init wraps that field in a builder
  closure specifically to get trailing-closure syntax at the call site; a tuple
  type has no parameter position for that syntax to attach to, and a closure
  isn't `Equatable`, storable, or diffable. `makeFlow(_:)` re-wraps the plain
  value into a trivial closure for the init: `footer: { flow.2 }`.
- **A static function, not a second `init`** — deliberately, so it works the same on
  a struct, class, or actor. A delegating second `init` (`init(...)`) requires
  the `convenience` keyword on a class/actor and drags in Swift's
  designated/convenience init rules; a plain static function returning `Self(...)`
  sidesteps that entirely.
- **Direct field forwarding**, not a trick. `Self(x: flow.0, y: flow.1)`
  — not `[layout].map(Self.init).first!`, which is what you'd reach for by hand to
  get an *unapplied* `Self.init` reference to accept a tuple positionally (it works,
  but the macro doesn't need it: it already knows every field's position). Fields
  are read positionally — `flow.0`, `flow.1`, … in field order — since the tuple
  is unlabeled.
- **Positional, unlabeled parameter (`_ flow:`)** — a deliberate naming choice,
  so the call site reads `Type.makeFlow(someFlow)`.

### The InFlow typealias

The same fields and types as `makeFlow(_:)`'s parameter, but **labeled** —
`(id: UUID, name: String)`, not `(UUID, String)`. Same collapse/absence rules
(one property → bare type, zero → nothing).

```swift
let named: User.InFlow = (id: someID, name: "Ada")
```

Labeled specifically for readable spelling (`named.id`, not `named.0`) and real
reflection support — verified directly: `Mirror(reflecting:)` reports each field's
actual name over a *labeled* tuple, but only positional labels (`.0`, `.1`) over an
*unlabeled* one, so the unlabeled parameter alone can't back a generic
field-name utility. `InFlow` can — see [`Reflector`](#reflector) below. An `InFlow`-typed value
feeds `makeFlow(_:)` with no conversion (an unlabeled parameter accepts any
labels — verified directly).

Deliberately nothing more. No accessor reading an instance back out into an
`InFlow`: data flows in at construction, and nothing needed the backward
read. No field-names member: `Reflector.fieldNames(of:
SomeType.InFlow.self)` already reports any generated tuple's names (see
[Reflector](#reflector)). And snapshotting private wrapper state is
[`Core`](#shell)'s job — a nominal struct conforms to protocols and hosts
live; a tuple can't, and a tuple of `$state` bindings wouldn't write
through outside a live view anyway (verified directly, `@State` and
`@SceneStorage` both).

### How makeFlow and InFlow relate

```mermaid
flowchart LR
    IF["InFlow<br/>(labeled tuple — the readable,<br/>Mirror-reflectable name)"]
    IFS["unlabeled tuple<br/>(makeFlow's parameter, spelled inline)"]
    IF -. "converts into<br/>(unlabeled accepts any label)" .-> IFS
    IFS -- "makeFlow(_:)" --> T((Self))
```

Both spell the same shape; only the unlabeled one sits in a parameter
position. **Honest caveat:** the flow members are declared mainly *because
the properties are already collected* for the init — cheap API surface, real
`Mirror` support — not because real code has demanded them yet. The diagram
below makes that distinction explicit.

**Why tuples, not a dedicated generated struct per type:** a tuple is a
*structural* type — two tuples with the same element types match regardless of
where they came from, with no shared nominal declaration needed. That's
exactly what a data-flow shape wants: `InFlow` needs to convert into
`makeFlow(_:)`'s unlabeled parameter, and so does any external,
differently-labeled tuple, without this package generating (and you naming) a
bespoke struct type for every field combination across every `@Flowable`
type. A nominal type would need its own declaration, its own name, and
explicit conversion code between every pair that should interoperate — an
independent named type *per shape*, i.e. type explosion. Tuples sidestep all
of it: the shape itself *is* the type.

### Why each member exists — structure vs. motivation

The diagram above shows how the pieces convert into each other; it doesn't
show *why* each one is there. They don't all have the same reason:

```mermaid
flowchart TD
    props(["stored properties<br/>collected once"])
    props --> init["init<br/>the actual reason @Flowable exists —<br/>Swift won't synthesize a public one"]
    props --> flow["makeFlow(_:) / InFlow<br/>free once properties are collected —<br/>tuple construction and Mirror support,<br/>not proven demand yet"]
    props --> node["Core (@Shell)<br/>earns its keep: construct directly<br/>with mocks, assert, host live —<br/>a real type: View / ViewModifier,<br/>Equatable, Codable, ..."]
```

- **`init`** — not optional, not speculative: it's the specific gap `@Flowable`
  fills (Swift only synthesizes an *internal* memberwise init, never a public
  one).
- **`makeFlow(_:)`/`InFlow`** — a byproduct of already
  having collected the properties for the init. Cheap to generate, genuinely
  useful *if* you need tuple construction or `Mirror`-based field names — the
  package's own tests exercise them
  (`Reflector.fieldNames(of: Point.InFlow.self)`), but only to demonstrate
  they work, not because another feature needed them to. Nothing
  else here depends on `InFlow` existing.
- **`Core`** — [`@Shell`](#shell)'s member, over the same collected
  properties: the one with a demonstrated reason to exist — testability
  without a live view — as a real type where a generated tuple structurally
  couldn't follow (real `View`/`ViewModifier` conformance,
  `Equatable`/`Codable`, generic code needing a shared protocol).

---

## Capability

A `member` macro that bundles every eligible **computed** property and method of the
type — or extension — it's attached to into one `Capability` tuple typealias and a
`capability` computed property: a lightweight "protocol witness"-style bundle of
*behavior*, as opposed to `@Flowable`'s `InFlow` typealias, which bundles
*data*. The idea is Scott Wlaschin's capability-based design
("Designing with capabilities" — see [References](#references)):
instead of handing a consumer the whole object (or a protocol it must
conform to), hand it exactly the functions it's entitled to call, as plain
values.

```swift
struct Counter {
    private var count = 0
}

@Capability
extension Counter {
    var doubled: Int { count * 2 }
    func increment() { /* ... */ }
    func fetch() async throws -> Int { count }
}
// generates:
// typealias Capability = (doubled: Int, increment: () -> Void, fetch: () async throws -> Int)
// var capability: Capability {
//     (doubled, increment, fetch)
// }
```

### Works on an extension — unlike @Flowable, on purpose

`@Flowable` collects **stored** properties, and extensions can never declare
those — so there's nothing for it to find if attached to one; that's a hard Swift
rule, not a missing feature. `@Capability` collects **computed** members instead,
which extensions declare just as freely as a primary type body, so it works equally
well attached directly to a struct/class/actor or to an extension of one.

### What's collected

- **Computed properties** (`var x: Int { ... }`) — needs an explicit type
  annotation, same syntax-only reasoning as the other macros. Stored properties
  (including ones with only `willSet`/`didSet`) don't participate.
- **Instance methods** — turned into a closure type from the parameter types
  (labels dropped, matching how closure types work), `async`/`throws` effects, and
  return type (`Void` if omitted).
- **Skipped**: `private`/`fileprivate`, `static`/`class`, initializers, subscripts,
  and `mutating` methods — Swift can't form a plain closure reference to a mutating
  method on a value type, so including one would generate code that doesn't
  compile.

One eligible member collapses `Capability` to that member's bare type/value — same
1-tuple collapse `@Flowable`'s `InFlow` typealias does, for the same reason
(Swift has no 1-tuples). Zero eligible members is a diagnostic, not an empty
`Capability`.

### No `@Sendable`

The generated closure fields are deliberately **not** marked `@Sendable`. Verified
directly, both ways: marking them unconditionally makes the generated code fail to
compile for any type that captures something non-Sendable (a plain class reference,
say) — `error: converting non-Sendable function value to '@Sendable () -> Void' may
introduce data races`. Omitting it compiles cleanly regardless, and still permits
genuine cross-`Task`/actor usage in practice: Swift 6's region-based Sendable
checking runs at the point the tuple literal is actually built (inside the
generated `capability` getter), independent of whether the field's declared type
says `@Sendable`.

---

## #pick (TuplePicker)

One macro, one shape: `#pick(from: value, \.a, \.b)`. One, two, or three sources —
arity-generic overloads of the exact same syntax, resolved by the compiler like any
other overloaded function, sharing one implementation.

### The idea

```swift
typealias Store = (expenses: [Int], limit: Int, name: String)
typealias Actions = (alerts: [String], submit: () -> Void)

let store: Store = (expenses: [12, 40, 7], limit: 100, name: "Groceries")
let actions: Actions = (alerts: ["low battery"], submit: {})

let picked = #pick(from: store, \.name, \.limit => "total")
// → (name: store.name, total: store.limit) — one source, renamed and reordered

let merged = #pick(from: store, \.expenses, \.limit, from: actions, \.alerts)
// → (expenses:, limit:, alerts:) — two sources, one tuple
```

Single key path returns the bare value (Swift has no 1-tuples); several return a labeled
tuple in exactly the order you wrote them. `=>` renames a field's output label without
giving up KeyPath typing or implicit-root inference. Works on structs, classes, and bare
tuple values — see below for why that last one wasn't a given. A second (or third) source
is just another `from:` group in the same call.

Every source starts with a real `from:` label — there's exactly one shape for `#pick`,
whether it's one source or three, dispatched to the right arity-generic overload by
Swift's own overload resolution (argument count), backed by a single implementation
(`PickMacro`).

### Run it

- `swift test` — macro-expansion + diagnostic tests (`assertMacroExpansion`) and an
  end-to-end suite that compiles and runs real `#pick` calls, across arities.
- Open `Package.swift` in Xcode, right-click a `#pick` call → **Expand Macro** to see the
  full emission inline.

### Honest limitations (each one was hit, argued, and verified against the real compiler)

#### `#pick`'s labels are cosmetic, not static

Every arity's declared signature returns a parameter pack (one source: `(repeat each
V1)`; two sources: `(repeat each V1, repeat each V2)`, one pack per source concatenated;
and so on), and parameter packs can't carry per-element labels in today's Swift. The
expansion body *does* build a labeled tuple literal (visible via "Expand Macro"), but at
the call site the value's static type is the unlabeled pack expansion, so labels get
silently stripped on assignment. Access the result by index (`.0`, `.1`), not by field
name — see `EndToEndTests.pickSingleFieldReturnsBareValue`.

#### Rename via a real argument label — a hard wall for one field, verified twice; fine for a whole source

The natural way to write a single-field rename would be
`#pick(from: store, \.expenses, total: \.limit)` — a real Swift argument label attached
to *one element* inside the picks. **This cannot work, full stop, no matter how `#pick`
is declared.** Verified two ways: first as a plain generic function with a loosely-typed
`Any...` tail, then directly against the real compiled `#pick` macro:

```
error: extra argument 'total' in macro expansion
    let __labelProbe = #pick(from: store, \.expenses, total: \.limit)
                                                        ^
```

Argument-label matching happens against the callee's *declared parameter list* — and a
variadic/pack parameter is one parameter, however many arguments it expands to. There is
no way to declare a parameter that accepts an arbitrary caller-chosen label attached to
one of its elements; loosening the type doesn't help, because the problem isn't type, it's
that `total:` doesn't match any declared parameter name at all.

The fix that ships for renaming *a field*: a custom operator. `\.limit => "total"` is a
*real* expression — the operator returns the same `KeyPath` type as its left operand — so
it type-checks against `repeat KeyPath<T, each V>` with full inference (implicit-root
`\.limit` keeps working). No loosened or untyped fallback needed; `#pick` never evaluates
`=>` at runtime, only reads its syntax to recover the label.

Two more walls along the way, both verified directly:

- The first operator spelling tried, `~>`, is **already declared by the Swift standard
  library itself** (unconditionally in scope everywhere). Redeclaring it collides:
  `error: ambiguous operator declarations found for operator`. `=>` was checked against
  the SDK's declared operators before shipping — collision-free.
- `\.i => .o` — using dot-shorthand instead of a string for the *rename target* — doesn't
  work for the same reason `#pick(from: p1, .x, .y)` (dot-shorthand instead of `\.x` for
  the *picked field*) doesn't: implicit-member syntax (`.foo`) only resolves against a
  real, predeclared member of the expected type. Even a static `@dynamicMemberLookup`
  subscript — the usual trick for open-ended `.anything` syntax — doesn't help; it still
  requires the compiler to accept the specific name, and rename targets are arbitrary.
  There's no Swift mechanism for an unregistered arbitrary identifier without a string.

Note the distinction from `from:` itself, below — that one is not an arbitrary
caller-chosen label attached to one pack element; it's a real, predeclared parameter name
marking the boundary *between* two separate pack parameters. Different mechanism, which is
exactly why it works where `total:` doesn't.

#### `#pick` uses a real, repeated `from:` label to mark source boundaries — verified, not assumed

Given the wall above, it would be reasonable to assume the labeled multi-source form
(`#pick(from: store, \.expenses, \.limit, from: actions, \.alerts)`) hits the same
"extra argument" error — which would force uglier alternatives like nested parens per
source. It doesn't, and the reason is specific: `from:` isn't an
arbitrary caller-chosen label inside one pack parameter (that's the impossible case) —
it's a *real, predeclared* parameter label that repeats once per source in the signature,
marking the boundary *between two separate* pack parameters:

```swift
func pick<T1, each V1, T2, each V2>(
    from a: T1, _ paths1: repeat KeyPath<T1, each V1>,
    from b: T2, _ paths2: repeat KeyPath<T2, each V2>
) -> (repeat each V1, repeat each V2) {
    (repeat a[keyPath: each paths1], repeat b[keyPath: each paths2])
}
```

Verified as a plain function first, including running it (not just type-checking) to
confirm the picks actually land in the right group — `pick(from: store, \.expenses,
\.limit, from: actions, \.alerts)` correctly split into `paths1 = [\.expenses, \.limit]`
and `paths2 = [\.alerts]`. Then verified as an actual macro declaration. One
implementation (`PickMacro`) reads the flat `from:`-labeled argument list for every
arity — one syntax, not two or three.

#### Tuple KeyPaths actually work — a widely-assumed limitation that's stale

Key paths into tuple elements have a long, widely known history of being "not
implemented" in Swift (a 2018 pitch; the identity-keypath half shipped as SE-0227, the
tuple half never did) — an assumption that would force workarounds like mirror
structs bridging picks onto tuple values. No workaround is needed.

Verified directly against a modern toolchain, with real execution:

```swift
let t = (a: 1, b: "x")
let kp = \(a: Int, b: String).a       // → WritableKeyPath<(a: Int, b: String), Int>
t[keyPath: kp]                        // → 1, correct
```

Implicit root, explicit root, heterogeneous field types, positional tuples, and the `=>`
rename operator all work on tuple values with **zero changes** to `#pick`'s declaration.
If you're targeting an older toolchain, verify this specific claim before relying on it.

#### `#pick` can't nest inside a call resolving to the *same declared overload* — but nesting across different arities works, and that distinction was verified, not assumed

`#pick(from: #pick(from: t, \.a, \.b), \.a)` where both calls resolve to the one-source
overload — does not compile: `error: recursive expansion of macro 'pick(from:_:)'`.

The outer macro expands first and, as you'd expect for macro composition in general,
treats the inner call as opaque tokens, copying it verbatim into its own body. That's
where composition would stop cleanly if the two calls resolved to different overloads.
Here they don't: the compiler walks the outer's freshly-produced body for more macros to
expand with "currently expanding `pick(from:_:)`" still on the stack, finds the inner call
resolving to that exact same overload, and refuses.

The working form for same-overload nesting is two separate statements — different
expansion sites, no shared stack:

```swift
let inner = #pick(from: store, \.expenses, \.limit)
let outer = #pick(from: inner, \.0)
```

— which is what `EndToEndTests.pickOfPickComposesOnATupleValue` exercises.

**Nesting a call that resolves to a *different arity's* overload is a different story, and
it works** — verified directly, including at runtime, not just type-checked:

```swift
let nested = #pick(from: #pick(from: store, \.expenses, \.limit), \.1 => "total", from: actions, \.alerts)
```

Here the inner call resolves to the one-source overload (`pick(from:_:)`) and the outer to
the two-source one (`pick(from:_:from:_:)`) — genuinely surprising, since both overloads
are backed by the exact same implementation type (`PickMacro`) after the multi-arity
unification. It would be reasonable to assume the recursion guard is keyed on *that*
implementation-type identity and refuses any nesting once two overloads share one — that
assumption was checked directly and is wrong. Probed empirically both ways: the two-arity
nesting above compiled *and* ran correctly (`(100, ["low battery"])`, matching
`store.limit` renamed and `actions.alerts`), while the same-arity nesting one section up
failed with the exact "recursive expansion" error, on this same shared-implementation
setup. So the guard's actual key is the resolved **declared overload** (its full compiler
signature, e.g. `pick(from:_:)` vs. `pick(from:_:from:_:)`) — not the spelled macro name
(confirmed earlier, before unification, by aliasing two different implementation types
under one name and nesting between them), and not the backing implementation type either
(confirmed now, by unifying two overloads onto one implementation type and finding nesting
between them still works). This composition isn't in the examples, though — writing a
one-source pick as one source's value inside a multi-source call is real but contrived;
nobody reaches for it by default, so it stays here as a documented fact, not a headline
example.

#### Multi-source `#pick`'s pack-of-packs typing — spiked before writing the macro, not assumed

The two- and three-source overloads need a return type that concatenates one parameter
pack per source — `(repeat each V1, repeat each V2)` for two sources. Verified as a plain
(non-macro) generic function first, including a call site to confirm real type inference,
not just that the declaration parses (same function shown above, under "uses a real,
repeated `from:` label").

It typechecked, both declaration and call site — Swift accepts multiple independent
pack expansions concatenated in one tuple type. A fourth source has no matching overload
and falls back to a plain "no matching function" diagnostic; not currently worth a fourth
typed overload for one more source.

#### One shape, no "which mode am I" detection to get wrong

An earlier version of this package had a single macro implementation detect "grouped"
calls by inspecting whether the first argument was a parenthesized tuple. That had a real,
documented sharp edge: detection read *only* argument 0, so a call whose first source
happened to have no picks yet misread as flat and produced a confusing error pointing at
the wrong argument. The current design has no shape to guess at all: every arity reads the
identical flat, `from:`-labeled argument list, dispatched to the right overload by Swift's
own overload resolution (argument count) before `PickMacro`'s expansion function ever
runs. `PickMacro` never asks "which mode is this" — its diagnostics (missing leading
`from:`, a source with no picks, a non-key-path token) all read the same flat list the
same way regardless of how many sources are present.

### Next steps if you keep going

1. **Evolution revival post**: "Tuple element KeyPaths" — worth confirming what shipped,
   where, and since when, on toolchains older than the one this was verified against.
2. **Labeled parameter packs**: if Swift ever supports per-element labels on `repeat each V`,
   every arity could return a genuinely labeled tuple instead of a positional one.
3. **Same-overload nesting, if it ever matters**: `#pick(from: #pick(from: ...), ...)`
   where both resolve to the exact same arity — a distinct declared overload (reachable via
   a hidden internal alias, say) would dodge the recursion guard the same way nesting
   across different arities already does, since the guard is keyed on declared-overload
   identity, not implementation type. Not shipped; two-statement composition covers the
   real need today.

---

## Reflector

Not a macro — a small runtime utility (`Sources/CoreFlow/Reflector.swift`) shipped
alongside the macros because it's a natural companion to `@Flowable`, not because
it needs code generation.

```swift
Reflector.fieldNames(of: User.InFlow.self)   // ["id", "name"]
```

One static function: `fieldNames<T>(of: T.Type) -> [String]`. It needs only the
*type* — no instance — so it can name an `InFlow`'s fields without ever
constructing one.

### How it works

It allocates one **uninitialized** `T` and reads its field labels via `Mirror`:

```swift
static func fieldNames<T>(of: T.Type) -> [String] {
    precondition(!(T.self is AnyClass), "fieldNames requires a value type, got class \(T.self)")
    let p = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { p.deallocate() }
    return Mirror(reflecting: p.pointee).children.compactMap(\.label)
}
```

This is safe *specifically* because it only ever reads `.label`, never `.value`.
`Mirror`'s labels come from `T`'s compile-time field-descriptor metadata; a child's
actual value is only lazily materialized (and ARC-retained, for a class-typed field)
if something accesses `.value` — which this function never does.

### Requires a value type — checked at runtime, not compile time

Swift has no generic constraint for "not a class," and a marker-protocol workaround
wouldn't help either, since tuples can't conform to a protocol to opt in — so this is
a `precondition`, not something the type system can catch. Verified directly that
SwiftUI has the identical gap: a `final class` conforms to `View` and compiles fine;
"views are structs" is convention, not compiler-enforced.

The crash this guards against is about **`T`'s own top-level kind, not its fields** —
verified directly, both ways:

- A bare class as `T` (`Reflector.fieldNames(of: SomeClass.self)`) crashes with a
  null-pointer trap: `Mirror` has to cast the top-level value to `CustomReflectable`
  before looking at any field, and uninitialized memory read as a class reference
  fails that cast.
- A **struct** containing a class-typed (or closure, or array) field is fine — same
  uninitialized-memory read, but `Mirror` never needs to validate or retain that
  child just to report its label.

### Pairs with @Flowable

Point it at `InFlow`:

```swift
@Flowable
struct Point {
    var x: Int
    var y: Int
}

Reflector.fieldNames(of: Point.InFlow.self)   // ["x", "y"]
Reflector.fieldNames(of: (Int, Int).self)     // [".0", ".1"] — unlabeled tuples have only positional labels
```

An unlabeled tuple isn't wrong to reflect on — it just has no real labels to
report, which is why `makeFlow(_:)`'s parameter shape isn't the one to point
`Reflector` at. `InFlow` is the one built for this.

---

## Deliberately no protocol naming the shape

There is no `FlowableRepresentable` protocol (`associatedtype InFlow`,
`static func makeFlow(_:) -> Self`) for
writing generic code against "any `@Flowable` type" by constraint. Decided
against: without real generic-code use cases, such a protocol's only value
is naming a shape `@Flowable` already generates concretely on every type
it's attached to.

---

## Package layout

One target pair shared by all macros — not a pair per macro:

| Target | Kind | Contents |
|---|---|---|
| `CoreFlowMacros` | macro plugin | every macro's implementation: `FlowableMacro`, `ShellMacro`, `CapabilityMacro`, `PickMacro`, one file each, `TestSupportMacros.swift` (`@TestState` + `@TestAction`), `TestFocusStateMacro.swift` (`@TestFocusState`), and `UnstructuredTaskMacro.swift` (`@UnstructuredTask`) — plus shared stored-property collection (`StoredProperty.swift`) and rendering (`FlowableRendering.swift`, covering the init, `makeFlow(_:)`, and `InFlow`) that `@Flowable` builds on and `@Shell` reuses (`ShellRendering.swift`), and TuplePicker's own key-path parsing (`KeyPathPick.swift`, `TuplePickerSupport.swift`) |
| `CoreFlow` | library (the one product) | every macro's public declaration — `Flowable.swift`, `Shell.swift`, `Capability.swift`, `TuplePicker.swift`, `TestSupport.swift` (`@TestState`/`@TestAction`, `View.testLog(_:)`, and the `TestLog` dynamic property), `TestFocusState.swift` (`@TestFocusState`), `UnstructuredTask.swift` (`@UnstructuredTask` plus its runtime `TaskStorage` box and `CancellableTask` protocol) — plus two small non-macro additions: `Reflector.swift` and `QueryCore.swift` |
| `CoreFlowTests` | test (XCTest + swift-testing) | `assertMacroExpansion` coverage per macro, plus real-compiled end-to-end suites (TuplePicker, Reflector, Shell's `Core`, `QueryCore`, the test-support macros) — both test frameworks coexist fine in one target |

Swift tools version 6.3, Swift 6 language mode (strict concurrency), swift-syntax `600.0.0..<700.0.0`.

---

## References

The conceptual model, taught macro-free — the split these macros mechanize:

- Lazar Otasevic — [SwiftUI Data Flow Masterclass](https://medium.com/@redhotbits/swiftui-data-flow-masterclass-099f0768f776) — nodes, waves, boundary events, the shell/core split, execution-log testing

Data-flow programming and data coupling — the model behind the package as a
whole: a SwiftUI app as nodes (views, view modifiers) coupled only by the
plain data flowing between them:

- Ian Cooper — [Hustle and Flow](https://www.youtube.com/watch?v=p0bKMuBdpL8) (NDC Porto 2022) — Flow-Based Programming (J. Paul Morrison): a system as nodes communicating through flows of discrete data packets
- Ian Cooper — [Succeeding at Reactive Architecture](https://www.youtube.com/watch?v=YyWKczrfxW4) (NDC London 2023) — the reactive properties, and message/data passing as the coupling discipline that unlocks them

Functional core, imperative shell — the pattern behind `@Shell`/`Core`:

- Gary Bernhardt — [Boundaries](https://www.destroyallsoftware.com/talks/boundaries)
- Scott Wlaschin — [Six approaches to dependency injection](https://fsharpforfunandprofit.com/posts/dependencies/) (pushing I/O to the edges)
- Mark Seemann — [Impureim sandwich](https://blog.ploeh.dk/2020/03/02/impureim-sandwich/)

Capability-based design — the idea behind `@Capability`:

- Scott Wlaschin — [Designing with capabilities](https://fsharpforfunandprofit.com/cap/)

Against ViewModels/`ObservableObject` in SwiftUI — why `@StateObject`/`@ObservedObject` stay unmapped:

- Lazar Otasevic — [Why MVVM Fails in SwiftUI](https://medium.com/@redhotbits/why-mvvm-fails-in-swiftui-47f73b05b458)
- Lazar Otasevic — [The Logical Fallacy Behind Your Broken SwiftUI Mental Model](https://medium.com/@redhotbits/from-science-to-swiftui-the-reification-of-behavior-1800f86a6aed)
