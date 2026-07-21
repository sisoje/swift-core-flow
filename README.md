# ValueFlow

A small, growing collection of independent Swift macros, all shipped from one
library — a single dependency gets you every macro below:

```swift
// Package.swift
.package(url: "https://github.com/sisoje/swift-value-flow.git", from: "1.0.0"),

// target dependency
.product(name: "ValueFlow", package: "ValueFlow"),
```

Requires Swift 6.3+ (`swift-tools-version: 6.3`). Builds across the whole swift-syntax
6xx line. Run everything with `swift build && swift test`; see every macro exercised
together in `Sources/Examples/main.swift` (`swift run Examples`).

## What's inside

| Macro | Form | Does |
|---|---|---|
| [`@Shell`](#shell) | member | generates a nested, nominal `Core` struct capturing a `View`/`ViewModifier`'s full externally-relevant state — real `Equatable`/`Codable`/protocol conformance a tuple can never have |
| [`@Flowable`](#flowable) | member | writes a memberwise `init` at the type's own access level, plus `InFlowSplat`/`InFlow` typealiases bundling the same properties into a tuple, unlabeled and labeled, plus a wider `OutFlow` — the tuple `@Shell`'s `Core` doesn't replace |
| [`@Capability`](#capability) | member | bundles every eligible computed property/method into a `Capability` tuple + computed property — works on an extension |
| [`#pick`](#pick-tuplepicker) | expression | projects one or more fields — via KeyPath — from one or more sources into a single tuple |
| [`Reflector`](#reflector) | runtime utility (not a macro) | lists a value type's field names off its type alone, no instance needed — pairs with `@Flowable`'s `InFlow` |

---

## Shell

A `member` macro, separate from `@Flowable` — it doesn't replace `OutFlow`/
`outFlow`, and works with or without `@Flowable` also attached (it collects the
type's stored properties itself). It generates a nested `Core` struct —
always internal (the struct, every field, and the `core` property
itself), regardless of the attached type's own access level, and carrying no
`@Flowable` — plus a `core` computed property building one from the
current instance. Its field set is identical to `OutFlow`'s (see the
[wrapper mapping reference](#wrapper-mapping-reference)): every non-private
participating property, plus every recognized private source-of-truth
wrapper, each captured once as a plain value.

```swift
@Shell
struct Card: View {
    @Query private var items: [Item]
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var isExpanded = false
    let title: String
    var subtitle: String?
    // generates:
    // struct Core {
    //     @QueryCore var items: [Item]
    //     let colorScheme: ColorScheme
    //     @Binding var isExpanded: Bool
    //     let title: String
    //     let subtitle: String?
    // }
    // var core: Core {
    //     Core(items: QueryCore(wrappedValue: _items.wrappedValue,
    //               fetchError: _items.fetchError, modelContext: _items.modelContext),
    //               colorScheme: colorScheme, isExpanded: $isExpanded,
    //               title: title, subtitle: subtitle)
    // }
}
```

### Wrapper mapping reference

Every wrapper kind this package recognizes, and exactly what it becomes on
`@Shell`'s nested `Core` struct — one row each, no grouping. Types are left
out below on purpose: each attribute already implies its own type (`@Binding`
→ `Binding<T>`, `@QueryCore` → `QueryCore<T>`, and so on — spelled out in
full later in this doc). `OutFlow` follows the same shape, minus the
`let`/`var`/attribute keyword.

This table is every *source of truth* this package recognizes, plus the plain
`let`/`var` baseline they're all measured against — `@Binding` and `@Bindable`
are the two public exceptions, included because they still need a row.
`@ViewBuilder` isn't one: it's not a source of truth, and its only real nuance
is covered in the [SwiftUI](#swiftui) section below and the last bullet below
the table. Every source-of-truth row must be private, enforced with a
diagnostic, not just convention.

| Shell | Core | Read as |
|---|---|---|
| `let`/`var` | `let` | `x` |
| `@Binding` | `@Binding` | `$x` |
| `@Bindable` | `@Bindable` | `x` |
| `@Environment` | `let` | `x` |
| `@Namespace` | `let` | `x` |
| `@ScaledMetric` | `let` | `x` |
| `@Query` | `@QueryCore` | `QueryCore(_x)` |
| `@GestureState` | `@GestureStateCore` | `GestureStateCore($x)` |
| `@State` | `@Binding` | `$x` |
| `@AppStorage` | `@Binding` | `$x` |
| `@SceneStorage` | `@Binding` | `$x` |
| `@FocusState` | `@FocusState.Binding` | `$x` |
| `@AccessibilityFocusState` | `@AccessibilityFocusState.Binding` | `$x` |

> **`@StateObject` and `@ObservedObject` are NOT supported, on purpose.**
> They're Combine-era `ObservableObject` wrappers, and this package doesn't
> recognize either one — declaring one `private` (their normal form) is a
> compile error (an unrecognized private wrapper), by design, rather than
> silently falling out of `OutFlow`/`Core` unnoticed. This isn't a gap to
> fill in later: this package's whole `@Flowable`/`@Shell` model is
> built for plain, `Equatable`-friendly data and SwiftUI's own native property
> wrappers, not `ObservableObject`/MVVM-style state containers.

**A few things worth spelling out beyond the table above — the last one is about
`@ViewBuilder`, which isn't a row in it at all (see why above):**

- **`@Binding` reads `$x`, not `_x`.** Verified: `Binding`'s own
  `projectedValue` is `{ self }`, so both give the identical `Binding<T>` —
  `$x` is just the same convention every `Binding`-producing row already
  uses, no `@Binding`-only special case.
- **`@FocusState` can't share `@State`/`@AppStorage`/`@SceneStorage`'s field
  type, even though all four are read via `$x`.** Those three wrappers'
  `projectedValue` genuinely *is* `Binding<T>`. `@FocusState`'s is a distinct
  type, `FocusState<T>.Binding` — verified directly against the real SwiftUI
  interface: it exposes only `wrappedValue` and `projectedValue` (itself), no
  public initializer and no conversion to `Binding<T>`. A hand-built
  `Binding(get:set:)` stand-in was considered and rejected — it would satisfy
  neither `.focused(_:)` nor anything else expecting the real projection back.
  The real `FocusState<T>.Binding` is itself `@propertyWrapper`-attributed
  (verified directly), so it redeclares onto `Core` the same way
  `@Binding` does, just spelling a different wrapper — `snap.x` reads the
  unwrapped value, `snap.$x` hands back a real `FocusState<T>.Binding` usable
  directly with `.focused(_:)`. `@AccessibilityFocusState` is an exact clone
  of this shape (verified directly) and gets the identical treatment —
  `snap.$x` feeds `.accessibilityFocused(_:)`.
- **`@QueryCore` is a real, one-to-one drop-in for the live `@Query`.**
  Verified directly against the `_SwiftData_SwiftUI` interface: `Query`'s
  instance surface is exactly `wrappedValue`, `fetchError`, and
  `modelContext`, with **no `projectedValue`** — so `QueryCore` carries the
  same three and nothing else. `core.items` reads the fetched value directly,
  and `_items.fetchError`/`_items.modelContext` work the same way they do on
  the live wrapper — body code moves onto `Core` unchanged. Capturing
  `modelContext` outside a live container is safe (verified directly, no
  crash).
- **`@GestureStateCore` is the same drop-in move for `@GestureState`,
  wrapping the captured live instance whole.** Its surface is exactly
  `wrappedValue` (get-only) + `projectedValue` (itself, what `.updating(_:)`
  takes) — verified directly against the SwiftUI interface — and both are
  forwarded, so `.updating($dragOffset)` in `Core`'s body is byte-identical
  to the live property's wiring. Mockable by seeding:
  `GestureStateCore(GestureState(wrappedValue: mock))` reads back the mock
  outside a live view (verified directly), so a test/preview renders `Core`
  as if mid-gesture.
- **`@ViewBuilder`'s two stored forms get opposite treatment, on purpose.** A
  stored *closure* (`let content: () -> Content`) already has a closure-typed
  field, so mirroring `@ViewBuilder` is pure upside — real builder syntax at
  `Core`'s own init call site. A stored *value* (`let footer:
  Content`) does **not** keep the attribute: mirroring it there would make
  Swift's own synthesized init wrap the parameter in a builder closure purely
  to satisfy the attribute (verified directly) — overhead with no benefit for
  a value that's already built and just being copied through. So `footer`
  stays a plain `let footer: Content`, passed straight through with no
  wrapping needed on either side.

### Why a nominal struct alongside `OutFlow`'s tuple

Tuples can't conform to protocols — verified directly against the real compiler:

```
type '(x: Int, y: String)' cannot conform to 'Equatable'
only concrete types such as structs, enums and classes can conform to protocols
```

So `OutFlow` alone can never be `Equatable`, `Codable`, or conform to a shared
"any stateless snapshot" protocol for generic code to work with. `Core` is a
real nominal struct capturing the same data, so it can — for free, the moment it's
declared as a real `struct`.

### Why `Core` is always internal, and carries no `@Flowable`

`Core` is a purely internal testing/snapshot seam — `.core` for
assertions, plus a `Core`-hosted `body`/`body(content:)` implementation
— not part of the attached type's public API, even when that type itself is
`public`: consumers of a public host never need the snapshot, only the
package's own tests do (reachable from the same module, or a `@testable
import`). So the struct, every field, and `core`'s own access are
always internal, never mirroring the attached type's access level.

No hand-rolled init is needed either. Swift's own memberwise-init synthesis
already reproduces every field-specific behavior `@Flowable` would generate
by hand — verified directly: a property-wrapper field with no
`init(wrappedValue:)` (`@Binding`) synthesizes a parameter of the *wrapper's*
type, one that does (`@Bindable`) synthesizes a parameter of the *wrapped*
type, and `@ViewBuilder` directly on a stored `let` synthesizes a real
builder parameter for the stored-closure form (see below) — exactly what
`@Flowable` would hand-write. The one thing genuinely lost by skipping
`@Flowable` is
`InFlow`/`InFlowSplat`/`inFlow`/`makeFlow(_:)` on `Core` itself,
accepted since nothing here needs to round-trip a snapshot back into itself.

Because `Core`'s own type is always internal, `core`'s access
is forced internal too — Swift rejects a more-accessible property with a
less-accessible type (verified directly: "property must be declared internal
because its type uses an internal type"). `body`/`body(content:)` on the
*attached* type, by contrast, still mirrors that type's own access (`public`
included) — verified directly that this compiles even though it reads
`core` (internal) and returns it: `some View`'s opaque return
type only exposes the `View` conformance, never the concrete `Core`
type, so a `public` `body` can freely return an internal concrete value.

### Every source-of-truth wrapper becomes a plain, constructed value

Every private source-of-truth wrapper becomes an ordinary field on
`Core`, captured once rather than kept live — never the original
attribute, except where the field mapping table above shows a substitution
(`@Binding`, or `@FocusState<T>.Binding` for `@FocusState`). The two fields with
no `Binding`-shaped projection to substitute — `@Environment` and
`@Namespace` — fall back to a plain `let name: T` instead: not because the
value doesn't change, but because the *attribute* can't be preserved (both
wrappers' `wrappedValue` is get-only — verified directly for `@Environment`:
`error: cannot assign to property: 'colorScheme' is a get-only property` —
and the synthesized init always assigns `self.x = x`, which a plain
unattributed `let` has no trouble with). Always `let` here, not mirroring the
original's `let`/`var` (always `var`, every property wrapper requires it) —
the captured copy is a one-time snapshot, immutable by design.

**All seven recognized source-of-truth wrappers must be private — enforced
with a diagnostic, not accommodated.** They're a view's own source of truth,
never something a caller supplies (`@Binding` is for that); declaring one
non-private is a compile error, so every renderer downstream can assume all
seven are always private, with no "what if it's also public" case to reason
about. A private field carrying some *other*, unrecognized wrapper
(`@StateObject`, `@GestureState`, a future SwiftUI wrapper, …) is refused by a
separate diagnostic rather than silently falling through as ordinary opaque
private state and quietly disappearing from `OutFlow`/`Core`.

### The rule for everything else: mirror the attribute and type, never the mutability

Every field except `@Query` (and `@Environment`, above) is declared on
`Core` with the *original* property's own attribute (if it has one) and
declared type — reusing `OutFlow`'s own field-computing functions
(`outFlowProperties`/`outFlowFieldType`/`outFlowFieldReadExpression`) unchanged to
decide *what* each field's type is — but never the original's `let`/`var`.
`Core` is a deterministic snapshot, so a field is `var` only where Swift's
own property-wrapper rule forces it (a genuine `@propertyWrapper` type requires
`var` storage; verified directly, `@Bindable let model: Settings` is a compile
error: "property wrapper can only be applied to a 'var'"). Everything else —
including `@Query`'s synthesized tuple above — is `let`, regardless of what the
original property was declared as.

This one rule covers several things at once:

- **A plain `var subtitle: String?` becomes `let subtitle: String?` on
  `Core`** — a captured value, not a re-tweakable one.
- **A genuine, already-public `@Binding` field mirrors verbatim** into exactly
  the same `@Binding var name: T` form `@State`/`@AppStorage` are substituted
  into above — it already *is* that declaration in the original source, so no
  extra logic is needed. `@Flowable`'s existing `@Binding` handling (a
  `Binding<T>` init parameter, assigned to the backing `_name` storage)
  picks up both cases identically. The payoff: `core.name` reads the
  wrapped value directly, no `.wrappedValue` unwrap — and `core.name =
  newValue` writes straight through to whatever storage the original binding
  pointed at, genuinely two-way. `@Binding` is itself a genuine property
  wrapper, so it keeps `var`.
- **`@ViewBuilder` mirroring is a real win here, unlike `OutFlow`'s tuple —
  but only for the stored-*closure* form** (`let content: () -> Content`):
  the field type is already a closure there, so the attribute is pure
  upside — real builder syntax at `Core`'s own init call site, not
  just documentation. For a stored *value* (`let footer: Content`), mirroring
  the attribute would make Swift's own synthesized init wrap the parameter in
  a builder closure purely to satisfy it (verified directly) — overhead with
  no benefit for a value that's already built and just being copied through —
  so it's dropped there entirely: `footer` stays a plain `let footer:
  Content`, passed straight through in `core` with no wrapping on
  either side. `@ViewBuilder` is *not* a `@propertyWrapper` — it's a
  result-builder attribute, legal directly on `let` (verified directly:
  `@ViewBuilder let vb: () -> Text` compiles).
- **`@Bindable` needs no special handling beyond the general "genuine wrapper
  keeps var" rule above** — no init logic here ever recognized `@Bindable`
  specially even on the *original* type (it just does `self.model = model`,
  legal since `@Bindable`'s wrappedValue is a plain get/set), so mirroring it
  onto `Core` works identically under Swift's own synthesized init.

### Automatic `View`/`ViewModifier` detection

When the attached type's own inheritance clause spells `View` or `ViewModifier`,
`@Shell` generates two more things beyond the usual struct/property pair:

```swift
@Shell
struct Card: View {
    let title: String
    // generates, in addition to the usual Core struct/core property:
    // struct Core: View { ... }       <- conformance declared, not implemented
    // var body: some View { core }   <- the mechanical delegation, for free
}

// only the real implementation is left to write by hand:
extension Card.Core {
    var body: some View { Text(title) }
}
```

`ViewModifier` works the same way — `struct VM: ViewModifier` gets `Core:
ViewModifier` plus `func body(content: Content) -> some View {
content.modifier(core) }`, going through `View.modifier(_:)` rather
than forwarding `content` directly into `Core`'s own `body(content:)`. That
detour is required, not stylistic: `ViewModifier.Content` is `typealias Content =
_ViewModifier_Content<Self>`, a generic struct keyed on the *conforming type
itself*, so `VM`'s own `Content` and `VM.Core`'s are different concrete
types — verified directly against the real compiler:

```
error: cannot convert value of type 'VM.Content' (aka '_ViewModifier_Content<VM>')
to expected argument type 'VM.Core.Content' (aka '_ViewModifier_Content<VM.Core>')
note: arguments to generic parameter 'Modifier' ('VM' and 'VM.Core') are expected to be equal
```

`.modifier(_:)` only needs its argument to conform to `ViewModifier`, not to
share a `Content` — it sidesteps the whole problem.

**This detection is syntactic, not semantic.** A macro never gets a type
checker, so it can only read the literal inheritance clause written on the
attached declaration itself — conformance added in a separate extension
elsewhere, via a typealias or protocol composition, or spelled with a
qualification (`SwiftUI.View`), is invisible to it. Only a bare `View`/
`ViewModifier` identifier directly on the attached type is recognized.

**How you're expected to discover you need to write that extension at all**:
`Core: View`/`: ViewModifier` only *declares* the requirement, so Swift's
own "does not conform to protocol" build error already forces the extension to
exist — but that error alone doesn't say *where* (extend `Card.Core`, not
`Card`). `@Shell` also generates a doc comment directly on the `Core`
struct declaration, spelling out exactly what to write, visible via Quick
Help/jump-to-definition. Deliberately a doc comment, not a compiler diagnostic:
the macro has no way to know whether the extension already exists elsewhere in
the module, so a `.note`/`.warning` would either nag forever (never clears
once implemented) or never fire at all. A doc comment costs nothing once the
extension is written.

### How a Core relates to its host

Every value a stateful host needs comes from exactly one of two places — supplied
from *outside* by a caller, or held as the runtime's own *source of truth* — and
both kinds converge on the host, which does nothing with them itself beyond
handing them to `Core`. All the real rendering logic, and every view
modifier, lives in `Core`'s own hand-written `body`/`body(content:)` —
which is why it's constructible and testable with no live view in the picture
at all:

```mermaid
flowchart TD
    subgraph Outside["from outside — caller-supplied"]
        Bind["@Binding<br/>e.g. isOn"]
        Plain["plain fields<br/>e.g. title"]
    end

    subgraph SOT["source of truth — runtime-managed"]
        State["@State / @AppStorage"]
        Query["@Query"]
        Env["@Environment"]
    end

    Outside --> Card
    SOT --> Card

    subgraph Card["Card — stateful, live"]
        CardBody["body<br/>(generated delegation)"]
    end

    subgraph SN["Card.Core — pure value, real View"]
        Fields["captured fields<br/>@Binding (writes through) · let (frozen)"]
        SNBody["body<br/>hand-written — ALL rendering logic<br/>and view modifiers live here"]
        Fields --> SNBody
    end

    CardBody -. "core<br/>captures every value once" .-> SN
    Test(["unit test / preview"]) -. "construct Core directly —<br/>no live view, no environment, no ModelContext" .-> Fields
```

- **`Outside`/`SOT` → `Card`** — `Card` is just where the two kinds of input
  meet, not where any logic lives: values the caller supplies (`@Binding`,
  plain fields) and values the runtime itself owns and can change underneath
  it (`@State`/`@Query`/`@Environment`/`@AppStorage`) arrive the same way, as
  far as anything downstream is concerned.
- **`CardBody -.-> SN`** (dotted, generated automatically) — the one moment
  every value gets captured, once, into `Fields`: a live `@Binding` becomes a
  writable `@Binding` field (genuinely two-way), everything else freezes into
  a `let`. Exists only when `Card` is detected as `View`/`ViewModifier`, and
  it's pure mechanical delegation — nothing hand-written on `Card`'s side.
- **`Fields` → `SNBody`** — the part you *do* write by hand: real rendering
  logic and every view modifier, reading only already-captured, plain data —
  no live view, no environment injection, no `ModelContext` required to
  exercise it.
- **`Test -.-> Fields`** (dotted, the other way in) — the path that skips
  `Card` entirely: construct a `Core` directly — in a unit test, or a
  `#Preview` — and assert on or render its captured fields, no live rendering
  pipeline required.

---

## Flowable

A `member` macro that writes a memberwise `init` for the type it's attached to, **at
the type's own access level**. It fills the initializers Swift won't synthesize: the
`public init` a public struct needs, and *any* init for a `class` or `actor` —
including an `@Observable final class`. Alongside the init, it also declares two
typealias/accessor pairs — an unlabeled `InFlowSplat` with a `makeFlow(_:)`
factory building `Self` back *from* one, and a labeled `InFlow` with an
`inFlow` computed property reading the current instance's data back *out* —
plus a wider `OutFlow`/`outFlow` pair mixing `InFlow`'s
fields with a view's own externally-relevant private state. See
[below](#the-inflowsplat-typealias), [below that](#the-makeflow_-factory),
[below that](#the-inflow-typealias), [below that](#the-inflow-property), and
[below that](#the-outflow-typealias-and-outflow-property).

See the [diagram below](#how-inflow-and-outflow-relate) for how the whole shape
fits together.

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
// public typealias InFlowSplat = (UUID, Bool)
// public static func makeFlow(_ flow: InFlowSplat) -> Self {
//     Self(id: flow.0, isActive: flow.1)
// }
```

Works the same on a `class` or `actor`:

```swift
@Flowable
@Observable final class Counter {
    var count = 0
}
// init(count: Int = 0) { self.count = count }
// typealias InFlowSplat = Int          // one property → bare type, not a 1-tuple
// static func makeFlow(_ flow: InFlowSplat) -> Self { Self(count: flow) }
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

- **`private` properties are excluded** from the init. Since SwiftUI's view-owned
  wrappers — `@State`, `@Environment`, `@StateObject`, … — are always `private`, they
  fall out automatically. No configuration, no per-wrapper list.
- **`@Binding`** is threaded in as a projected `Binding<T>` parameter, assigned to the
  backing storage (`self._x = x`).
- **`@ViewBuilder`** carries onto the parameter so callers get trailing-closure syntax.
  A stored closure (`let content: () -> Content`) becomes `@ViewBuilder content: @escaping () -> Content`;
  a stored value (`let footer: Content`) becomes `@ViewBuilder footer: () -> Content` and the
  init calls it (`self.footer = footer()`).

```swift
@Flowable
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme   // excluded (private)
    @State private var expanded = false              // excluded (private)
    @Binding var isOn: Bool                           // init param: Binding<Bool>
    let title: String
    @ViewBuilder let footer: Content                  // init param: @ViewBuilder () -> Content

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
- **`private` means private, and it must mean something.** If a value is meant to be
  passed in, it isn't private — `@Binding`/`@Bindable`/`@ViewBuilder` declared private
  are unreachable by any caller and are rejected outright. And a private property with
  no recognized wrapper at all (`private var cache = 0`) isn't quietly excluded
  anymore either — it's neither a source of truth nor something a caller supplies, so
  pure data flow has no room for it: give it a real wrapper, or make it non-private.

### The InFlowSplat typealias

Alongside the init, `@Flowable` declares `InFlowSplat` — the same properties
bundled into a tuple type, for API uniformity/discoverability (e.g. `Foo.InFlowSplat`
is always there to reference generically) rather than as a second constructor;
nothing in the init routes through it.

```swift
@Flowable
public struct User {
    public let id: UUID
    public let name: String
}
// public typealias InFlowSplat = (UUID, String)

let flow: User.InFlowSplat = (id: someID, name: "Ada")
```

It's built independently of the init, so it diverges from it in a few ways:

- **Unlabeled** — `(UUID, String)`, not `(id: UUID, name: String)` — deliberately,
  so any structurally-compatible tuple converts into it, not just one built with
  these exact field names ("splat" in the name). Verified directly: a tuple
  *value* already bound with different labels (`let t = (xxx: 1, yyy: 2)`) fails
  to convert into a *labeled* tuple type of the same shape (`error: cannot
  convert value of type '(xxx: Int, yyy: Int)' to expected argument type '(x:
  Int, y: Int)'`), but succeeds once the target is unlabeled — Swift only
  enforces label agreement between two *labeled* tuple types. A labeled tuple
  *literal* (`(id: someID, name: "Ada")`, as above) converts into an unlabeled
  target either way, so you can still write field names for your own
  readability when constructing the value — only a pre-existing,
  differently-labeled variable needed the loosening. The real cost: with no
  labels, the compiler no longer catches two same-typed fields passed in the
  wrong order.
- **No per-field defaults.** Tuple element types can't carry `= default` — so an
  inline `var` default, and an optional `var`'s implicit `nil`, are both dropped,
  unlike the init right above it.
- **One property still gets an `InFlowSplat` — just not a tuple.** Swift has no
  1-tuples — `(Int)` as a type collapses to plain `Int` regardless of labels — so
  with exactly one participating property, `InFlowSplat` aliases the bare field
  type directly (`typealias InFlowSplat = Int`).
- **Zero properties → no typealias at all.** There's nothing to alias, and the init
  already covers the zero-property case on its own (`init() {}`).
- **Never `@escaping`**, even on function-typed fields — a closure nested inside a
  tuple type is already escaping; writing the attribute there is a compile error.
- **`@ViewBuilder` is ignored entirely.** A stored-value field
  (`@ViewBuilder let footer: Content`) keeps its own type in the typealias
  (`Content`, not `() -> Content`) and would be assigned directly if anything
  consumed it. The init wraps that field in a builder closure specifically to get
  trailing-closure syntax at the call site; a tuple type has no parameter position
  for that syntax to attach to, so the wrapping would buy nothing here — and would
  actively work against the point of `InFlowSplat`, which is data you pass
  around, store, or diff, not a closure.

### The makeFlow(_:) factory

A `static func makeFlow(_ flow: InFlowSplat) -> Self` that builds an instance from
an `InFlowSplat` value — declared whenever `InFlowSplat` itself is (same
collapse/absence rules). It forwards each field directly:

```swift
let flow: User.InFlowSplat = (id: someID, name: "Ada")
let user = User.makeFlow(flow)

// Any structurally-compatible tuple works, not just one built with these field
// names — InFlowSplat is unlabeled:
let differentlyLabeled = (uuid: someID, label: "Ada")
let user2 = User.makeFlow(differentlyLabeled)
```

- **A static function, not a second `init`** — deliberately, so it works the same on
  a struct, class, or actor. A delegating second `init` (`init(...)`) requires
  the `convenience` keyword on a class/actor and drags in Swift's
  designated/convenience init rules; a plain static function returning `Self(...)`
  sidesteps that entirely.
- **Direct field forwarding**, not a trick. `Self(x: flow.0, y: flow.1)`
  — not `[layout].map(Self.init).first!`, which is what you'd reach for by hand to
  get an *unapplied* `Self.init` reference to accept a tuple positionally (it works,
  but the macro doesn't need it: it already knows every field's position).
- **Fields are read positionally** — `flow.0`, `flow.1`, … in field
  order — since `InFlowSplat` itself is unlabeled.
- **A `@ViewBuilder`-stored value is the one field that isn't forwarded as-is.**
  `InFlowSplat` holds it as a plain value, but the primary init still wants a
  `() -> Content` builder for it — so `makeFlow(_:)` wraps it back into a
  trivial closure: `footer: { flow.2 }`.
- **Positional, unlabeled parameter (`_ flow:`)**, not a labeled `make(inFlowSplatted:)`
  — a deliberate naming choice, so the call site reads `Type.makeFlow(someFlow)`.

### The InFlow typealias

The reverse direction from `InFlowSplat`: the same fields and types, but **labeled**
— `(id: UUID, name: String)`, not `(UUID, String)`. Same collapse/absence rules
(one property → bare type, zero → nothing).

```swift
let named: User.InFlow = (id: someID, name: "Ada")
```

Labeled specifically for readable field access (`named.id`, not `named.0`) and real
reflection support — verified directly: `Mirror(reflecting:)` reports each field's
actual name over a *labeled* tuple, but only positional labels (`.0`, `.1`) over an
*unlabeled* one, so `InFlowSplat` alone can't back a generic field-name utility.
`InFlow` can — see [`Reflector`](#reflector) below.

### The inFlow property

A computed property extracting the *current* instance's values into an
`InFlow` — the reverse of `makeFlow(_:)`. Declared whenever
`InFlow` is.

```swift
let user = User(id: someID, name: "Ada")
user.inFlow   // (id: someID, name: "Ada")

// Round-trips through makeFlow(_:) with no manual conversion — an
// InFlow value converts into InFlowSplat's unlabeled parameter the same
// way any differently-labeled tuple does:
let copy = User.makeFlow(user.inFlow)
```

- Every field reads straight off `self` (`x`) — except `@Binding`, which
  reads its projected form (`$x`) to match `InFlowSplat`'s `Binding<T>` field
  type.
- **No `@ViewBuilder` wrapping needed here**, unlike `makeFlow(_:)`'s reverse
  direction: a stored property already holds exactly its own declared type
  regardless of `@ViewBuilder` — that attribute only ever reshapes the *init
  parameter*, never the property's own storage.

### The OutFlow typealias and outFlow property

Wider than `InFlow`/`inFlow`: `InFlow`'s fields, **plus every recognized
private source-of-truth wrapper** — `@Query`/`@State`/`@AppStorage`/
`@SceneStorage`/`@FocusState`/`@Environment`/`@Namespace` — a view's own
externally-relevant *capturable* state, alongside its public data, no
exceptions. There's no such thing as "everything else private" left over —
a private property either carries one of these recognized wrappers or it's a
compile error (see [Design: for pure data](#design-for-pure-data)) — see the
[wrapper mapping reference](#wrapper-mapping-reference) for exactly what each
recognized kind becomes.

**Why this exists: testability.** Any SwiftUI node that owns or reads live
state via one of these wrappers introduces a source of truth that only really
works inside a live render pipeline — view identity, a real `ModelContext`,
the current environment. That makes it hard to test directly. `OutFlow`
converts that state into a plain, stateless snapshot: construct the type,
read `.outFlow`, assert on the fields — no live view hierarchy needed. That's
the actual point of targeting exactly these wrapper kinds, not "expose
private state" for its own sake — and it's also why there's no exception for
`@Environment`/`@Namespace`: a captured value going stale, or `@Environment`'s
own mocking story, are things to know about the *snapshot*, not reasons to
leave the field out of it — `@Shell` never excluded either one, and
`OutFlow` shouldn't either.

```swift
@Flowable
struct Card: View {
    @Query private var items: [Item]
    @State private var isExpanded = false
    let title: String
    // generates:
    // typealias OutFlow = (items: QueryCore<[Item]>,
    //                       isExpanded: Binding<Bool>, title: String)
    // var outFlow: OutFlow {
    //     (items: QueryCore(wrappedValue: _items.wrappedValue,
    //          fetchError: _items.fetchError, modelContext: _items.modelContext),
    //      isExpanded: $isExpanded, title: title)
    // }
}
```

- **Declaration order, as one interleaved list** — not data-layout fields first
  with wrapper fields appended after. `items` comes first above because it's
  declared first.
- **`@Query` → always `QueryCore<WrappedType>`** — this package's own drop-in
  stand-in for the live wrapper, not a passthrough of the declared type; see
  the [wrapper mapping reference](#wrapper-mapping-reference) for the
  one-to-one details.
- **`@State`/`@AppStorage`/`@SceneStorage` → `Binding<WrappedType>`**, read via
  the *projected* value (`$x`) — not `_x`, which gives the wrapper instance
  itself (`State<T>`, not `Binding<T>`; verified directly).
- **Every recognized wrapper needs an explicit type even though it's
  private** — every other private property is exempt from that rule, but
  `OutFlow` reads the type to build its field. `@Namespace` is the one
  exception: its wrapped type is always `Namespace.ID`, so there's nothing to
  annotate.
- **`@State`'s `Binding` doesn't write through outside a live SwiftUI view
  render** — verified directly: construct a `@Flowable` type in plain code
  (never installed into a real view hierarchy) and mutate
  `outFlow.someStateField.wrappedValue` — it silently no-ops instead of
  persisting. That's `@State`'s own behavior, not a bug here; a genuine
  caller-supplied `@Binding` field, by contrast, really does write through.
- **On a `View`-conforming type, reading `outFlow` needs `@MainActor`** — `View`
  conformance implicitly infers `@MainActor` isolation for the whole type, so
  touching its members from a nonisolated context (a plain function, a
  non-`@MainActor` test) crosses that isolation boundary at runtime and can trap
  under Swift 6 strict concurrency. A plain top-level script doesn't hit this —
  top-level code already runs on the main actor.

### Testing a @Flowable type's state

`OutFlow` in practice: construct the type directly, no `ModelContainer`, no
`WindowGroup`, no live rendering — just read `.outFlow` and assert:

```swift
@MainActor
@Suite struct CardTests {
    @Test func startsCollapsed() {
        let card = Card(title: "Settings")  // items/isExpanded are private, excluded from init
        #expect(card.outFlow.isExpanded.wrappedValue == false)
        #expect(card.outFlow.title == "Settings")
    }
}
```

`@MainActor` on the suite is required, not stylistic, whenever the type
conforms to `View` — see the bullet above. See
`Tests/ValueFlowTests/OutFlowTests.swift` for the real version of this pattern,
including the one genuine caveat: a `@State`-derived binding read through
`outFlow` doesn't write back outside a live view (see two bullets up) — reading
its *value* for assertions works fine, mutating it in a test doesn't stick.

An earlier revision also had an `allFieldNames` static var here, unconditionally
listing *every* stored property's name with no filtering — including plain
private fields with no recognized wrapper (`private var cache = 0`, legal at
the time), which never appeared in `InFlowSplat`/`InFlow`/`OutFlow` either. It
was removed once it became clear [`Reflector`](#reflector) already covers the
same need for any *specific* generated tuple
(`Reflector.fieldNames(of: SomeType.OutFlow.self)`, say) without a dedicated
member. The gap that removal opened — a totally-private, non-wrapper field has
no tuple anywhere to reflect over — is moot now anyway: that kind of field is a
compile error (see [Design: for pure data](#design-for-pure-data)), not a
silently-excluded one.

### How InFlow and OutFlow relate

```mermaid
flowchart LR
    subgraph in["in — construction"]
        IFS["InFlowSplat<br/>(unlabeled tuple)"]
    end
    subgraph out["out — reading"]
        IF["InFlow<br/>(labeled tuple)"]
        OF["OutFlow<br/>(labeled tuple, wider)"]
    end
    IFS -- "makeFlow(_:)" --> T((Self))
    T -- "inFlow" --> IF
    T -- "outFlow" --> OF
    IF -. "converts into<br/>(unlabeled accepts any label)" .-> IFS
```

- **`InFlowSplat`/`makeFlow(_:)`** — data flowing *in*, to build a `Self`.
- **`InFlow`/`inFlow`** — the same fields flowing back *out*, labeled for
  reading — and, since it's structurally the same shape as `InFlowSplat`
  minus labels, it converts right back into `makeFlow(_:)`'s parameter with no
  manual conversion.
- **`OutFlow`/`outFlow`** — a wider *out*, adding the view's own
  externally-relevant *capturable* private state — every recognized
  source-of-truth wrapper (`@Query`/`@State`/`@AppStorage`/`@SceneStorage`/
  `@FocusState`/`@Environment`/`@Namespace`, no exceptions; see its own
  section above) — alongside the same public fields `InFlow` has. There's no
  `OutFlow`-shaped *in* direction — nothing constructs a `Self` from private
  view state, so this side of the diagram is deliberately one-way.

**Honest caveat on `InFlow`/`inFlow` specifically:** it's declared mainly
*because the properties are already collected* for the init and `InFlowSplat`
right next to it — free API symmetry, and real `Mirror` support (see
[Reflector](#reflector)) — not because real code has actually needed a
labeled, readable *out* tuple yet. `OutFlow` is the member with a proven
reason to exist (testability, demonstrated below); `InFlow` is closer to "it
costs nothing extra to generate, so it's here if you want it." The diagram
below makes that distinction explicit.

**Why tuples, not a dedicated generated struct per type:** a tuple is a
*structural* type — two tuples with the same element types match regardless of
where they came from, with no shared nominal declaration needed. That's
exactly what a data-flow shape wants: `InFlow` and `InFlowSplat` need to
convert into each other, and any external, differently-labeled tuple needs to
splat into `makeFlow(_:)`, without this package generating (and you naming) a
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
    props --> flow["InFlowSplat / makeFlow(_:)<br/>InFlow / inFlow<br/>free once properties are collected —<br/>symmetry and Mirror support,<br/>not proven demand yet"]
    props --> out["OutFlow / outFlow<br/>earns its keep: construct directly,<br/>assert on private state, no live view"]
    out --> node["Core<br/>same field set, plus @Environment —<br/>a real type: View / ViewModifier,<br/>Equatable, Codable, ..."]
```

- **`init`** — not optional, not speculative: it's the specific gap `@Flowable`
  fills (Swift only synthesizes an *internal* memberwise init, never a public
  one).
- **`InFlowSplat`/`makeFlow(_:)`/`InFlow`/`inFlow`** — a byproduct of already
  having collected the properties for the init. Cheap to generate, genuinely
  useful *if* you need splat-construction or `Mirror`-based field names — this
  package's own Examples/tests do exercise them (`Point.makeFlow(keke)`,
  `Reflector.fieldNames(of: Point.InFlow.self)`), but only to demonstrate they
  work, not because another feature in this package needed them to. Unlike
  everything below, nothing else here depends on `InFlow` existing.
- **`OutFlow`/`outFlow`** — the one with a demonstrated reason: testability
  without a live view (see [Testing a @Flowable type's
  state](#testing-a-flowable-types-state) and
  `Tests/ValueFlowTests/OutFlowTests.swift`).
- **`Core`** — builds on `OutFlow`'s same motivation, one step
  further: a real type where `OutFlow`'s tuple structurally can't follow (real
  `View`/`ViewModifier` conformance, `Equatable`/`Codable`, generic code
  needing a shared protocol).

---

## Capability

A `member` macro that bundles every eligible **computed** property and method of the
type — or extension — it's attached to into one `Capability` tuple typealias and a
`capability` computed property: a lightweight "protocol witness"-style bundle of
*behavior*, as opposed to `@Flowable`'s `InFlowSplat` typealias, which bundles
*data*.

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
1-tuple collapse `@Flowable`'s `InFlowSplat` typealias does, for the same reason
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

- `swift run Examples` — `#pick` combining multiple sources into one tuple, on plain
  tuple values, alongside the `@Flowable` examples.
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

An earlier revision required nested parens per source for multiple sources —
`#pick((store, \.expenses, \.limit), (actions, \.alerts))` — separate from the bare
single-source form. Given the wall above, it seemed reasonable to assume a labeled version
(`#pick(from: store, \.expenses, \.limit, from: actions, \.alerts)`) would hit the same
"extra argument" error. It doesn't, and the reason is specific: `from:` here isn't an
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
and `paths2 = [\.alerts]`. Then verified as an actual macro declaration, and finally
shipped: the nested-parens syntax and the separate single-source form were both dropped in
favor of one implementation (`PickMacro`) reading the flat `from:`-labeled argument list
for every arity — one syntax, not two or three.

#### Tuple KeyPaths actually work now — a premise this design once leaned on turned out stale

Key paths into tuple elements have a long, widely known history of being "not
implemented" in Swift (a 2018 pitch; the identity-keypath half shipped as SE-0227, the
tuple half never did). An earlier version of this package built an entire workaround
around that assumption — mirror structs to bridge picks onto tuple values.

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

Not a macro — a small runtime utility (`Sources/ValueFlow/Reflector.swift`) shipped
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

Point it at `InFlow`, not `InFlowSplat`:

```swift
@Flowable
struct Point {
    var x: Int
    var y: Int
}

Reflector.fieldNames(of: Point.InFlow.self)          // ["x", "y"]
Reflector.fieldNames(of: Point.InFlowSplat.self)  // [".0", ".1"] — InFlowSplat is unlabeled
```

`InFlowSplat` isn't wrong to reflect on — it just has no real labels to report, since
it's deliberately unlabeled (see [above](#the-inflowsplat-typealias)). `InFlow`
is the one built for this.

---

## FlowableRepresentable — removed

An earlier revision had a protocol here (`associatedtype InFlowSplat`,
`associatedtype InFlow`, `static func makeFlow(_ flow: InFlowSplat) -> Self`,
`var inFlow: InFlow { get }`) naming `@Flowable`'s generated shape, so generic
code could be written against "any `@Flowable` type" by constraint — opt-in,
via an empty `extension Point: FlowableRepresentable {}`. Removed: not enough
real generic-code use cases materialized to justify keeping a protocol whose
only value was naming a shape `@Flowable` already generates concretely on
every type it's attached to.

---

## Package layout

One target pair for every macro — not one pair per macro:

| Target | Kind | Contents |
|---|---|---|
| `ValueFlowMacros` | macro plugin | every macro's implementation: `FlowableMacro`, `ShellMacro`, `CapabilityMacro`, `PickMacro`, one file each — plus shared stored-property collection (`StoredProperty.swift`) and rendering (`FlowableRendering.swift`, covering the init, `InFlowSplat`/`InFlow`, and `OutFlow`) that `@Flowable` builds on and `@Shell` reuses (`ShellRendering.swift`), and TuplePicker's own key-path parsing (`KeyPathPick.swift`, `TuplePickerSupport.swift`) |
| `ValueFlow` | library (the one product) | every macro's public declaration — `Flowable.swift`, `Shell.swift`, `Capability.swift`, `TuplePicker.swift` — plus three small non-macro additions: `Reflector.swift`, `QueryCore.swift`, and `GestureStateCore.swift` |
| `ValueFlowTests` | test (XCTest + swift-testing) | `assertMacroExpansion` coverage per macro, plus TuplePicker's and Reflector's real-compiled end-to-end suites — both test frameworks coexist fine in one target |
| `Examples` | executable | one playground exercising every macro in the package, plus Reflector |

Swift tools version 6.3, Swift 6 language mode (strict concurrency), swift-syntax `600.0.0..<700.0.0`.
