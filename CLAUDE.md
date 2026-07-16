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
| `DataMacrosMacros` | macro plugin | every macro's implementation, one `@main` `CompilerPlugin` listing all of them. One file per macro (`MemberwiseInitMacro.swift`, `DataLayoutInitMacro.swift`, `DataInitMacro.swift`, `PickMacro.swift`), plus shared stored-property collection + rendering (`StoredProperty.swift`, `MemberwiseInitRendering.swift`, `DataLayoutInitRendering.swift`) and TuplePicker's own parsing (`KeyPathPick.swift`, `TuplePickerSupport.swift`) |
| `DataMacros` | library (the one product) | every macro's public attribute/expression declaration, one file per macro (`MemberwiseInit.swift`, `DataLayoutInit.swift`, `DataInit.swift`, `TuplePicker.swift`) |
| `DataMacrosTests` | test (XCTest + swift-testing, same target) | all coverage: `assertMacroExpansion` per macro, plus TuplePicker's real-compiled end-to-end suite |
| `Examples` | executable | combined playground for every macro |

Adding a new macro: one new file in `DataMacrosMacros` for the implementation
(`Foo­Macro: MemberMacro`/`ExpressionMacro`), add it to `Plugin.swift`'s
`providingMacros`, one new file in `DataMacros` for the public
`@attached`/`@freestanding` declaration pointing `#externalMacro(module:
"DataMacrosMacros", type: "FooMacro")`, a new `XCTestCase`/`@Suite` in
`DataMacrosTests`, and a `// MARK: -` section in `Examples/main.swift`. No new
Package.swift targets or products. If the macro generates an init from a type's
stored properties (like `@MemberwiseInit`, `@DataLayoutInit`, and `@DataInit` do),
build it on `StoredProperty.swift`'s collection and the existing `*Rendering.swift`
functions rather than re-deriving them — everything being one module is exactly what
makes that free (no cross-target `public`, no extra target wiring). A macro that
combines what two existing macros generate (like `@DataInit` combines
`@MemberwiseInit` + `@DataLayoutInit`) should collect stored properties **once** and
call each renderer directly, rather than being spelled as "stack the two existing
attribute macros" — stacking works when the two sets of generated members never
collide, but it collects (and diagnoses) the same properties once per stacked macro.

## @MemberwiseInit — tricky points

`member` macro that writes a memberwise `init` at the type's own access level, for a
struct, class, or actor. Entry point: `Sources/DataMacrosMacros/MemberwiseInitMacro.swift`.
Rendering: `renderMemberwiseInit` in `Sources/DataMacrosMacros/MemberwiseInitRendering.swift`.

- **Syntax-only, no type inference.** A non-private property that becomes a parameter
  needs an explicit type — `var count: Int = 0`, not `var count = 0` (the latter is a
  compile error). The macro can't read a type off a literal.
- **`private` is the one exclusion rule.** Every `private`/`fileprivate` property is
  dropped from the init. That single rule also keeps SwiftUI's view-owned wrappers out
  — `@State`/`@Environment`/`@StateObject` are always private — so there's no
  per-wrapper allow/deny list.
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

## @DataLayoutInit — tricky points

`member` macro, same property collection as `@MemberwiseInit` (same struct/class/actor
targets, same `private`/`@Binding`/`@ViewBuilder` rules — see above). Renders
differently: one tuple-typed `dataLayout` parameter instead of one parameter per
property. Entry point: `Sources/DataMacrosMacros/DataLayoutInitMacro.swift`.
Rendering: `renderDataLayoutMembers` in
`Sources/DataMacrosMacros/DataLayoutInitRendering.swift`.

- **Two or more properties** → `public typealias DataLayout = (x: T, y: U)` plus
  `public init(_ dataLayout: DataLayout)`, assigning `self.x = dataLayout.x`.
- **Exactly one property still gets a `DataLayout`, just not a tuple — and the init
  doesn't route through it.** Swift has no 1-tuples — `(x: T)` as a type collapses to
  plain `T`, no `.x` accessor — so `DataLayout` aliases the bare field type
  (`typealias DataLayout = T`, declared for API uniformity), but the init just uses
  the property's own name and type: `init(_ x: T) { self.x = x }`.
- **Zero properties** → `init() {}`, no typealias.
- **No per-field defaults.** Tuple element types can't carry `= default`, so an inline
  `var` default and optional-implies-`nil` are both *dropped* here — every field is
  required at the call site, unlike `@MemberwiseInit`'s per-parameter defaults.
- **Never `@escaping`, even on function-typed fields.** `@escaping` is only legal
  directly on a function parameter; here the parameter is the tuple (or the collapsed
  single field), so a closure nested inside it is already escaping — same reasoning
  as `@MemberwiseInit`'s optional-closure case, just applied to every function-typed
  field instead of only optional ones.
- **`@ViewBuilder` is ignored entirely — not just its call-site sugar.** A
  stored-value field (`@ViewBuilder let footer: Content`) keeps its own type
  (`footer: Content`) and is assigned directly (`self.footer = dataLayout.footer`),
  *not* turned into a `() -> Content` builder the init calls. `@MemberwiseInit` wants
  that wrapping — it's what buys trailing-closure syntax at the call site. That
  reason doesn't exist here (no parameter position inside a tuple literal for a
  trailing closure to attach to), and wrapping would actively hurt: `DataLayout` is
  meant to be data you pass around/store/diff, and a closure isn't `Equatable` or
  comparable. `baseTypeText`/`fieldAssignment` take a `wrapViewBuilder` flag for
  exactly this — `@MemberwiseInit` passes `true` (the default), `@DataLayoutInit`
  passes `false`.

## @DataInit — tricky points

`member` macro that generates both `@MemberwiseInit`'s and `@DataLayoutInit`'s
initializers from one attribute. Impl: `Sources/DataMacrosMacros/DataInitMacro.swift`
— collects properties once (`collectStoredProperties(..., macroName: "DataInit")`),
then calls `renderMemberwiseInit` and `renderDataLayoutMembers` directly and
concatenates.

- **Why not just stack `@DataLayoutInit @MemberwiseInit`?** That already works — the
  two generated initializers have different signatures at every property count except
  zero (see below), so nothing collides. `@DataInit` exists for one reason: stacking
  means two independent `collectStoredProperties` calls, so a property with a missing
  type annotation gets diagnosed **twice** (once per stacked macro). One collection
  pass fixes that; `DataInitTests.testMissingTypeIsDiagnosedOnceNotTwice` pins it down.
- **The two inits never collide, except at zero properties.** `init(x:y:)` (labeled,
  one per property) vs. `init(_ dataLayout: DataLayout)` (one unlabeled tuple
  parameter) are different signatures for 2+ properties; for exactly 1 property it's
  `init(x:)` (labeled) vs. `init(_ x:)` (unlabeled) — still distinct. At **zero**
  properties both renderers independently produce a bare `init()`, which *would*
  collide (`invalid redeclaration of 'init()'`) — `DataInitMacro` special-cases this
  and emits the shared `init()` once rather than calling both renderers.
- Otherwise inherits every rule from both macros above — read those two sections for
  the property model, `@Binding`/`@ViewBuilder` handling, and what's dropped
  (defaults, `@escaping`) in the `DataLayout`-shaped init specifically.

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
