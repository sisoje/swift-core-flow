# CLAUDE.md

A small, growing collection of independent Swift macros, all in ONE package/target
pair — not one target per macro. Consumers add a single dependency
(`.product(name: "DataMacros", package: "DataMacros")`) and get every macro; adding a
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
| `DataMacrosMacros` | macro plugin | every macro's implementation, one `@main` `CompilerPlugin` listing all of them. One file per macro (`MemberwiseInitMacro.swift`, `CapabilityMacro.swift`, `PickMacro.swift`), plus shared stored-property collection + rendering (`StoredProperty.swift`, `MemberMacroEntry.swift`, `FieldRendering.swift`, `MemberwiseInitRendering.swift`) that `@MemberwiseInit` builds on, and TuplePicker's own parsing (`KeyPathPick.swift`, `TuplePickerSupport.swift`) |
| `DataMacros` | library (the one product) | every macro's public attribute/expression declaration, one file per macro (`MemberwiseInit.swift`, `Capability.swift`, `TuplePicker.swift`) |
| `DataMacrosTests` | test (XCTest + swift-testing, same target) | all coverage: `assertMacroExpansion` per macro, plus TuplePicker's real-compiled end-to-end suite |
| `Examples` | executable | combined playground for every macro |

Adding a new macro: one new file in `DataMacrosMacros` for the implementation
(`Foo­Macro: MemberMacro`/`ExpressionMacro`), add it to `Plugin.swift`'s
`providingMacros`, one new file in `DataMacros` for the public
`@attached`/`@freestanding` declaration pointing `#externalMacro(module:
"DataMacrosMacros", type: "FooMacro")`, a new `XCTestCase`/`@Suite` in
`DataMacrosTests`, and a `// MARK: -` section in `Examples/main.swift`. No new
Package.swift targets or products. If the macro generates something from a type's
stored properties (like `@MemberwiseInit` does), build it on `StoredProperty.swift`'s
collection (`validatedProperties` in `MemberMacroEntry.swift`) and
`MemberwiseInitRendering.swift`'s functions rather than re-deriving them —
everything being one module is exactly what makes that free (no cross-target
`public`, no extra target wiring).

This package has gone through a few macro-boundary redesigns worth knowing about if
you're extending it further:

- **`@DataLayoutInit` used to be its own macro** — an init taking every stored
  property as one tuple-typed parameter, plus the `DataLayout` typealias describing
  that tuple. It's gone as a standalone macro now: the typealias half was folded
  directly into `@MemberwiseInit` (every `@MemberwiseInit` type gets a `DataLayout`
  typealias alongside its init, for free), and the "one tuple *parameter*" half was
  dropped entirely rather than carried over — `@MemberwiseInit`'s own init is
  unchanged, `DataLayout` is declared but nothing consumes it as a single init
  argument anymore. If a future macro wants that back, `renderDataLayoutTypealias`
  in `MemberwiseInitRendering.swift` already has the tuple-vs-bare-type collapse
  logic to build on.
- **`@DataInit`** generated both `@MemberwiseInit`'s and `@DataLayoutInit`'s
  initializers from one attribute — removed even before `@DataLayoutInit` was (see
  git history for both). If you want a macro that combines what two existing macros
  generate, the lesson from it still applies: collect stored properties **once** and
  call each renderer directly, rather than spelling it as "stack the two existing
  attribute macros" on the same type — stacking works when the two sets of generated
  members don't collide, but it collects (and diagnoses) the same properties once
  per stacked macro.

## @MemberwiseInit — tricky points

`member` macro that writes a memberwise `init` at the type's own access level, for a
struct, class, or actor — plus a `DataLayout` typealias bundling the same properties
into a tuple, and a `make(from:)` static factory building `Self` from one. Entry
point: `Sources/DataMacrosMacros/MemberwiseInitMacro.swift`. Rendering: all three —
`renderMemberwiseInit` (the init), `renderDataLayoutTypealias` (the typealias), and
`renderDataLayoutFactory` (`make(from:)`) — live in
`Sources/DataMacrosMacros/MemberwiseInitRendering.swift`; the latter two are called
from inside the first, so one macro expansion always produces all three together (or
just the init, if there are zero properties to alias/build from).

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

The `DataLayout` typealias — same property collection as the init above, rendered
differently:
- **Two or more properties** → `public typealias DataLayout = (x: T, y: U)`.
- **Exactly one property still gets a `DataLayout`, just not a tuple.** Swift has no
  1-tuples — `(x: T)` as a type collapses to plain `T`, no `.x` accessor — so
  `DataLayout` aliases the bare field type directly (`typealias DataLayout = T`).
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
  (`@ViewBuilder let footer: Content`) keeps its own type (`footer: Content`) in the
  typealias, *not* the `() -> Content` builder the init uses right above it. The init
  wants that wrapping — it's what buys trailing-closure syntax at the call site. That
  reason doesn't exist for a tuple type (no parameter position for a trailing closure
  to attach to), and wrapping would actively hurt: `DataLayout` is meant to be data
  you pass around/store/diff, and a closure isn't `Equatable` or comparable.
  `baseTypeText` (in `FieldRendering.swift`) takes a `wrapViewBuilder` flag for
  exactly this — the init's own rendering passes `true` (the default), the typealias
  rendering passes `false`.
- **The init doesn't route through the typealias** — `DataLayout` isn't a parameter
  of the init above. It's declared for API uniformity/discoverability (every
  `@MemberwiseInit` type has one to reference, e.g. in generic code) independent of
  the init's own signature.

The `make(from:)` factory — a `static func` (not a second `init`) building `Self`
from a `DataLayout`, present exactly when `DataLayout` is:
- **A static func, not a delegating `init`, specifically to work uniformly across
  struct/class/actor.** A second `init` calling `self.init(...)` needs the
  `convenience` keyword on a class/actor and drags in Swift's designated/convenience
  init rules; `Self(...)` inside a plain static function sidesteps that entirely.
- **Forwards each field directly** — `Self(x: dataLayout.x, y: dataLayout.y)` — not
  the `[layout].map(Self.init).first!` trick an *unapplied* `Self.init` reference
  needs to accept a tuple positionally. The macro already knows every field's name,
  so it just spells out the call.
- **A `@ViewBuilder`-stored value is the one field that isn't forwarded as-is.**
  `DataLayout` stores it as a plain value (`Content`), but the primary init still
  wants a `() -> Content` builder for it — so `make(from:)` wraps it back into a
  trivial closure: `footer: { dataLayout.footer }`.
- **Single-property collapse carries through unchanged.** When `DataLayout` is a
  bare type (not a tuple), `dataLayout` *is* the one field's value directly — no
  `.name` access: `Self(value: dataLayout)`.

## @Capability — tricky points

`member` macro that bundles every eligible *computed* property/method into a
`Capability` typealias + `capability` computed property. Entry point + collection +
rendering all live in `Sources/DataMacrosMacros/CapabilityMacro.swift` — doesn't
share `StoredProperty.swift`'s model at all (that's for *stored* properties; this
macro is deliberately about the opposite thing, and mixes properties with methods,
which `StoredProperty` has no concept of).

- **Works on an extension, unlike `@MemberwiseInit` — and that's not an oversight on
  its part.** `@MemberwiseInit` collects *stored* properties, and extensions can
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
  1-tuple collapse `@MemberwiseInit`'s `DataLayout` typealias does. **Zero** is a
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
`Sources/DataMacrosMacros/PickMacro.swift`, `KeyPathPick.swift`.

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
