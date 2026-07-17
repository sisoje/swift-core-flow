# DataMacros

A small, growing collection of independent Swift macros, all shipped from one
library — a single dependency gets you every macro below:

```swift
// Package.swift
.package(url: "https://github.com/<you>/DataMacros", from: "1.0.0"),

// target dependency
.product(name: "DataMacros", package: "DataMacros"),
```

Requires Swift 6.3+ (`swift-tools-version: 6.3`). Builds across the whole swift-syntax
6xx line. Run everything with `swift build && swift test`; see every macro exercised
together in `Sources/Examples/main.swift` (`swift run Examples`).

## What's inside

| Macro | Form | Does |
|---|---|---|
| [`@MemberwiseInit`](#memberwiseinit) | member | writes a memberwise `init` at the type's own access level, plus a `DataLayout` typealias bundling the same properties into a tuple |
| [`@Capability`](#capability) | member | bundles every eligible computed property/method into a `Capability` tuple + computed property — works on an extension |
| [`#pick`](#pick-tuplepicker) | expression | projects one or more fields — via KeyPath — from one or more sources into a single tuple |

---

## MemberwiseInit

A `member` macro that writes a memberwise `init` for the type it's attached to, **at
the type's own access level**. It fills the initializers Swift won't synthesize: the
`public init` a public struct needs, and *any* init for a `class` or `actor` —
including an `@Observable final class`. Alongside the init, it also declares a
`DataLayout` typealias bundling the same properties into an unlabeled tuple, and a
`make(dataLayout:)` static factory building `Self` back from one — see
[below](#the-datalayout-typealias) and [below that](#the-makedatalayout-factory).

```swift
@MemberwiseInit
public struct User {
    public let id: UUID
    public var isActive: Bool = false
}
// generates:
// public init(id: UUID, isActive: Bool = false) {
//     self.id = id
//     self.isActive = isActive
// }
// public typealias DataLayout = (UUID, Bool)
// public static func make(dataLayout: DataLayout) -> Self {
//     Self(id: dataLayout.0, isActive: dataLayout.1)
// }
```

Works the same on a `class` or `actor`:

```swift
@MemberwiseInit
@Observable final class Counter {
    var count: Int = 0
}
// init(count: Int = 0) { self.count = count }
// typealias DataLayout = Int          // one property → bare type, not a 1-tuple
// static func make(dataLayout: DataLayout) -> Self { Self(count: dataLayout) }
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
@MemberwiseInit
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

- **No type inference.** It's syntax-only: a non-private property that becomes a
  parameter needs an explicit type. `var count: Int = 0`, not `var count = 0` (the
  latter is a compile error).
- **No stored `let` constants.** A constant isn't per-instance data — use `static let`.
  The macro doesn't special-case an instance `let`: `let version: Int = 1` generates
  `self.version = version` (a `let`-reassignment error), and untyped `let version = 1`
  hits the missing-type rule above. Either way it won't compile.
- **`private` means private.** If a value is meant to be passed in, it isn't private.

### The DataLayout typealias

Alongside the init, `@MemberwiseInit` declares `DataLayout` — the same properties
bundled into a tuple type, for API uniformity/discoverability (e.g. `Foo.DataLayout`
is always there to reference generically) rather than as a second constructor;
nothing in the init routes through it.

```swift
@MemberwiseInit
public struct User {
    public let id: UUID
    public let name: String
}
// public typealias DataLayout = (UUID, String)

let layout: User.DataLayout = (id: someID, name: "Ada")
```

It's built independently of the init, so it diverges from it in a few ways:

- **Unlabeled** — `(UUID, String)`, not `(id: UUID, name: String)` — deliberately,
  so any structurally-compatible tuple converts into it, not just one built with
  these exact field names. Verified directly: a tuple *value* already bound with
  different labels (`let t = (xxx: 1, yyy: 2)`) fails to convert into a *labeled*
  tuple type of the same shape (`error: cannot convert value of type '(xxx: Int,
  yyy: Int)' to expected argument type '(x: Int, y: Int)'`), but succeeds once the
  target is unlabeled — Swift only enforces label agreement between two *labeled*
  tuple types. A labeled tuple *literal* (`(id: someID, name: "Ada")`, as above)
  converts into an unlabeled target either way, so you can still write field names
  for your own readability when constructing the value — only a pre-existing,
  differently-labeled variable needed the loosening. The real cost: with no labels,
  the compiler no longer catches two same-typed fields passed in the wrong order.
- **No per-field defaults.** Tuple element types can't carry `= default` — so an
  inline `var` default, and an optional `var`'s implicit `nil`, are both dropped,
  unlike the init right above it.
- **One property still gets a `DataLayout` — just not a tuple.** Swift has no
  1-tuples — `(Int)` as a type collapses to plain `Int` regardless of labels — so
  with exactly one participating property, `DataLayout` aliases the bare field type
  directly (`typealias DataLayout = Int`).
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
  actively work against the point of `DataLayout`, which is data you pass around,
  store, or diff, not a closure.

### The make(dataLayout:) factory

A `static func make(dataLayout: DataLayout) -> Self` that builds an instance from a
`DataLayout` value — declared whenever `DataLayout` itself is (same
collapse/absence rules). It forwards each field directly:

```swift
let layout: User.DataLayout = (id: someID, name: "Ada")
let user = User.make(dataLayout: layout)

// Any structurally-compatible tuple works, not just one built with these field
// names — DataLayout is unlabeled:
let differentlyLabeled = (uuid: someID, label: "Ada")
let user2 = User.make(dataLayout: differentlyLabeled)
```

- **A static function, not a second `init`** — deliberately, so it works the same on
  a struct, class, or actor. A delegating second `init` (`self.init(...)`) requires
  the `convenience` keyword on a class/actor and drags in Swift's
  designated/convenience init rules; a plain static function returning `Self(...)`
  sidesteps that entirely.
- **Direct field forwarding**, not a trick. `Self(x: dataLayout.0, y: dataLayout.1)`
  — not `[layout].map(Self.init).first!`, which is what you'd reach for by hand to
  get an *unapplied* `Self.init` reference to accept a tuple positionally (it works,
  but the macro doesn't need it: it already knows every field's position).
- **Fields are read positionally** — `dataLayout.0`, `dataLayout.1`, … in field
  order — since `DataLayout` itself is unlabeled.
- **A `@ViewBuilder`-stored value is the one field that isn't forwarded as-is.**
  `DataLayout` holds it as a plain value, but the primary init still wants a
  `() -> Content` builder for it — so `make(dataLayout:)` wraps it back into a
  trivial closure: `footer: { dataLayout.2 }`.

---

## Capability

A `member` macro that bundles every eligible **computed** property and method of the
type — or extension — it's attached to into one `Capability` tuple typealias and a
`capability` computed property: a lightweight "protocol witness"-style bundle of
*behavior*, as opposed to `@MemberwiseInit`'s `DataLayout` typealias, which bundles
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

### Works on an extension — unlike @MemberwiseInit, on purpose

`@MemberwiseInit` collects **stored** properties, and extensions can never declare
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
1-tuple collapse `@MemberwiseInit`'s `DataLayout` typealias does, for the same reason
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
  tuple values, alongside the `@MemberwiseInit` examples.
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

## Package layout

One target pair for every macro — not one pair per macro:

| Target | Kind | Contents |
|---|---|---|
| `DataMacrosMacros` | macro plugin | every macro's implementation: `MemberwiseInitMacro`, `CapabilityMacro`, `PickMacro`, one file each — plus shared stored-property collection (`StoredProperty.swift`) and rendering (`MemberwiseInitRendering.swift`, covering both the init and the `DataLayout` typealias) that `@MemberwiseInit` builds on, and TuplePicker's own key-path parsing (`KeyPathPick.swift`, `TuplePickerSupport.swift`). One `Plugin.swift` lists every macro type. |
| `DataMacros` | library (the one product) | every macro's public declaration — `MemberwiseInit.swift`, `Capability.swift`, `TuplePicker.swift` |
| `DataMacrosTests` | test (XCTest + swift-testing) | `assertMacroExpansion` coverage per macro, plus TuplePicker's real-compiled end-to-end suite — both test frameworks coexist fine in one target |
| `Examples` | executable | one playground exercising every macro in the package |

Swift tools version 6.3, Swift 6 language mode (strict concurrency), swift-syntax `600.0.0..<700.0.0`.
