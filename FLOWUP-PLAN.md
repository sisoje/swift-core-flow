# FlowUp — macro plan

`@Entry` = data flows down. `@FlowUp` = data flows up: closure data flowing up
is a view/modifier registering a listener with the injector above. The circle
closes downward again: the accumulator holds the accumulated listeners in its
own state and puts them into the environment, and any view reads a real
closure out of `@Environment` and calls it. One name spells every call site.

## Declaration (`Sources/CoreFlow/FlowUp.swift`)

```swift
@attached(accessor)
@attached(peer, names: arbitrary)
public macro FlowUp() =
    #externalMacro(module: "CoreFlowMacros", type: "FlowUpMacro")
```

Invocation — the `@Entry` idiom, one line, in the user's own
`extension EnvironmentValues`:

```swift
extension EnvironmentValues {
    @FlowUp var handleUrl: (URL) async throws -> Void
}
```

Name from the property name, closure type from the annotation. The anchor
becomes the consumer entry `handleUrl`; the peers are a same-named `static`
flow identifier (legal — static and instance members may share a name), plus
hidden machinery: `handleUrl_Key` — one enum that is both the
`EnvironmentKey` and the per-name tag keying the preference channel — and
the fileprivate entry `handleUrl_closures`. The anchor's declared access
level (e.g. `public var handleUrl`) is copied onto the accessor, the
static, AND `handleUrl_Key` — the static's return type names the
key-as-tag, so a public static requires a public key; a library can then
export a flow (accepting that a public key makes
`self[handleUrl_Key.self]` writable by consumers — harmless: the
accumulator clobbers manual writes on the next preference change). The
entry stays fileprivate regardless: keypaths carry the access rights of
where they were formed, so cross-module use needs only the named types
visible.

## Ergonomics — the three call sites, one name

```swift
// leaf: our view/modifier registers its callback, inside its own body
CardContent()
    .on(\.handleUrl) { url in
        // this card's reaction
    }

// injector: an ancestor accumulates every listener below it
ContentStack()
    .accumulate(\.handleUrl)

// consumer: anywhere under the injector — a REAL closure
@Environment(\.handleUrl) private var handleUrl
…
try await handleUrl(myUrl)
```

The trick: `on`/`accumulate` take a **metatype-rooted** keypath
(`KeyPath<EnvironmentValues.Type, FlowUpID<Tag, Closure>>`, SE-0438), so
their `\.handleUrl` resolves to the generated *static* member, while
`@Environment`'s instance-rooted `\.handleUrl` resolves to the anchor. Same
spelling, no ambiguity (probe-verified). The settable machinery entry is
fileprivate — invisible to `@Environment(\.` autocomplete; the keypath inside
the ID still drives `.environment(_:_:)` because a keypath carries the
access rights of where it was formed.

## Runtime (`Sources/CoreFlow/FlowUp.swift`, stable, not generated)

```swift
public final class FlowUpClosure<Closure>: Equatable, @unchecked Sendable {
    public internal(set) var closures: [Closure] = []

    public init() {}

    public static func == (lhs: FlowUpClosure, rhs: FlowUpClosure) -> Bool {
        lhs === rhs
    }
}

public struct FlowUpID<Tag, Closure> {
    let keyPath: WritableKeyPath<EnvironmentValues, [FlowUpClosure<Closure>]>

    public init(keyPath: WritableKeyPath<EnvironmentValues, [FlowUpClosure<Closure>]>) {
        self.keyPath = keyPath
    }
}

struct FlowUpPreferenceKey<Tag, Closure>: PreferenceKey {
    static var defaultValue: [FlowUpClosure<Closure>] { [] }

    static func reduce(
        value: inout [FlowUpClosure<Closure>],
        nextValue: () -> [FlowUpClosure<Closure>]
    ) {
        value += nextValue()
    }
}

struct FlowUpRegistration<Tag, Closure>: ViewModifier {
    let closure: Closure

    @State private var wrapper = FlowUpClosure<Closure>()

    func body(content: Content) -> some View {
        wrapper.closures = [closure]
        return content
            .transformPreference(FlowUpPreferenceKey<Tag, Closure>.self) { value in
                value.append(wrapper)
            }
    }
}

struct FlowUpAccumulator<Tag, Closure>: ViewModifier {
    let keyPath: WritableKeyPath<EnvironmentValues, [FlowUpClosure<Closure>]>

    @State private var listeners: [FlowUpClosure<Closure>] = []

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(FlowUpPreferenceKey<Tag, Closure>.self) { listeners in
                self.listeners = listeners
            }
            .environment(keyPath, listeners)
    }
}

extension View {
    public func on<Tag, Closure>(
        _ id: KeyPath<EnvironmentValues.Type, FlowUpID<Tag, Closure>>,
        _ closure: Closure
    ) -> some View {
        modifier(FlowUpRegistration<Tag, Closure>(closure: closure))
    }

    public func accumulate<Tag, Closure>(
        _ id: KeyPath<EnvironmentValues.Type, FlowUpID<Tag, Closure>>
    ) -> some View {
        modifier(
            FlowUpAccumulator<Tag, Closure>(
                keyPath: EnvironmentValues.self[keyPath: id].keyPath
            )
        )
    }
}
```

- **`FlowUpClosure`** — closures aren't Equatable; the class reference is the
  identity (ObjectIdentifier / `===`). Identity and payload are separate on
  purpose: the object IS the registration (stable for the view's lifetime),
  the `closures` array is what it currently listens with — empty at
  creation, one element after each body. The empty-array default gives the
  class a no-arg init, which is what lets the registration modifier's
  `@State` take an inline default. No `@escaping` anywhere: `Closure` is a
  generic parameter, closures bound to it are automatically escaping and the
  attribute is ill-formed there (probe-compiled both ways, Swift 6.4).
- **`FlowUpRegistration`** — the identity-churn fix: holds ONE wrapper in
  `@State` (same object across re-renders — the class-box-in-`State` pattern
  `@UnstructuredTask`'s `TaskStorage` already ships and locks in this
  package) and refreshes `wrapper.closures = [closure]` each body — a
  render-phase write to a plain object, touching no SwiftUI storage. The
  preference value therefore compares equal across waves and changes exactly
  when a registration appears or disappears (including a structural identity
  reset, which correctly re-registers). Without this, every leaf re-render
  would fire the accumulator, rewrite the environment, re-render all
  consumers, and add a wave-dependent `listeners` line to the log.
- **`FlowUpID`** — the flow's identity as a value: carries the writable
  keypath to the hidden entry, and its two phantom-ish generic parameters
  hand `Tag` and `Closure` to the generics at the call site. `Tag` makes
  same-signature flows distinct; the pairing makes a registration with the
  wrong closure shape fail to typecheck. Access split: `init` is public
  (generated code in the consumer's module constructs it), `keyPath` is
  internal — only `accumulate` reads it, and hiding it means no consumer can
  write the entry behind the accumulator's back.
- **`FlowUpPreferenceKey`** / **`FlowUpAccumulator`** — internal, not
  public: generated code never names them (only `FlowUpClosure` and
  `FlowUpID` appear in expansions), and consumers reach them solely through
  `on`/`accumulate` — a public generic func instantiates internal types
  fine. Smallest possible public surface: two types, two funcs.
- **`FlowUpPreferenceKey`** — the listener list travels as the bare wrapper
  array (already Equatable, reduce = old + new append), keyed uniquely per
  flow by `Tag`.
- **`FlowUpAccumulator`** — the whole injector: owns the state, catches the
  preference, and shoves the array straight into the environment for the
  same subtree — no conversion anywhere. No caller-side state, no binding.
- **`on(_:_:)` / `accumulate(_:)`** — hand-written generic View
  extensions in ordinary CoreFlow source, so the "macro expansion cannot
  introduce extension" wall never applies. `Tag` and `Closure` both infer
  from the ID keypath; registration never even resolves it (only the types
  matter); accumulation resolves it with `EnvironmentValues.self[keyPath:]`.

## Expansion

The accessor role turns the anchor into the consumer entry — a genuine
closure built over the hidden entry (this exact accessor-over-generated-peer
shape probe-compiled); the forwarding loop lives only here:

```swift
var handleUrl: (URL) async throws -> Void {
    let wrappers = self.handleUrl_closures
    return { url in
        for wrapper in wrappers {
            for closure in wrapper.closures {
                try await closure(url)
            }
        }
    }
}
```

The peer role generates the machinery, all inside the same user-written
`extension EnvironmentValues` (nested types are legal in a struct extension —
probe-verified, unlike the protocol-extension refusal):

```swift
enum handleUrl_Key: EnvironmentKey {
    static var defaultValue: [FlowUpClosure<(URL) async throws -> Void>] {
        []
    }
}

fileprivate var handleUrl_closures: [FlowUpClosure<(URL) async throws -> Void>] {
    get { self[handleUrl_Key.self] }
    set { self[handleUrl_Key.self] = newValue }
}

static var handleUrl: FlowUpID<handleUrl_Key, (URL) async throws -> Void> {
    FlowUpID(keyPath: \.handleUrl_closures)
}
```

Generated pieces:

- **`handleUrl` (the anchor's accessor)** — the consumer surface: a real
  `(URL) async throws -> Void`, calling every registered listener in order;
  passes anywhere a plain closure is expected. Read-only by construction.
  Empty entry → the loop is a no-op; the monoid empty.
- **`static handleUrl`** — the flow's identity for `on` / `accumulate`:
  same name, different namespace (metatype), a `FlowUpID` carrying the
  keypath to the hidden entry.
- **`handleUrl_Key`** — one enum, two jobs: the `EnvironmentKey` for the
  hand-rolled entry AND the per-name tag keying the preference channel (as
  the `Tag` argument of `FlowUpID`/`FlowUpPreferenceKey`); the floor of
  per-name generation. `defaultValue` is a *computed* static (a stored
  `static let` of the non-Sendable array is a strict-concurrency error).
  Delegating to native `@Entry` was tried and refused at compile time:
  `@Entry`'s own container check cannot see the extension from inside
  another macro's expansion buffer.
- **`handleUrl_closures`** — the fileprivate settable entry holding the
  bare wrapper array. Default `[]`, so everything works with no
  accumulator installed (listeners just never fire).

## Notes

- Forwarding arity comes from the written closure type and appears in
  exactly one generated spot — the anchor accessor's closure literal:
  `() -> Void` → `{ for … wrapper.closure() }`, `(A, B) -> Void` →
  `{ a, b in for … wrapper.closure(a, b) }`.
- Effects mirror the declared closure type (`try`/`await` added iff needed,
  like `@TestAction`): a plain `(URL) -> Void` flow generates everything
  effect-free. Policy: first thrown error aborts the remaining listeners;
  `async` runs listeners sequentially in registration order.
- Non-Void return types are diagnosed: N results have no single combination.
- Diagnostics (family policy — accessor expansion throws, peer role stays
  silent so the error reports once): annotation missing or not a function
  type, non-Void return, `let`, an inline default (the entry's `[]` default
  is generated, never user-supplied), and any non-single-stored-var shape.
- Main-actor contract: register and invoke on the main actor.
  `FlowUpClosure` is `@unchecked Sendable`, backed by that contract —
  mutation happens in registration bodies and reads at invocation, both
  main-actor in this design. The claim is REQUIRED, not optional: a
  `@MainActor`-typed flow makes the accessor's returned closure isolated,
  and sending the wrapper array into it is a region-isolation error
  (`sending 'wrappers' risks causing data races`) unless the array is
  Sendable — found by the compiled `@MainActor (Int) -> Void` flow in
  `FlowUpTests`. Not `@MainActor` on the class itself — that would break
  sync flows (their returned closure couldn't read `wrapper.closures`
  without an actor hop). Per-flow enforcement stays free at the
  declaration: `@FlowUp var handleUrl: @MainActor (URL) -> Void` rides
  verbatim through wrapper, entry, ID, and accessor (compiled test).
- Listener order is preference-traversal order; relative order across
  sibling branches is unspecified — documented as "don't depend on it".
- Verified by probes (Swift 6.4, 2026-08-12):
  - PASS (probe macro in this package): accessor + peer macro on a var
    inside user-written `extension EnvironmentValues` generating a nested
    struct, an `EnvironmentKey`, a settable sibling entry, and an accessor
    returning a closure over that sibling; user source referencing the
    generated members as keypath expressions and in type positions.
  - PASS (scratch compile): metatype-rooted keypath literal `\.handleUrl`
    inferring against `KeyPath<EnvironmentValues.Type, …>` (SE-0438);
    static + instance members sharing one name with no ambiguity in either
    keypath position; a static-returned keypath to a fileprivate entry
    driving reads/writes from outside the file.
  - PASS (scratch compile): generic-parameter closure storage needs no
    `@escaping` and refuses it (`'@escaping' only applies to function
    types`).
  - PASS (scratch compile, full planned runtime + two hand-expanded flows
    with the SAME closure signature): distinct preference-key types per tag;
    `.on(\.handleUrl) { url in … }` trailing-closure inference; both flows
    on one view; no collision with SwiftUI's `on*` family (`.onAppear`
    beside our `.on`); static ID keypath writing one flow's entry without
    touching the other. One requirement discovered: the generated key's
    `defaultValue` must be a *computed* `static var` — a stored `static let`
    of the non-Sendable wrapper array is a strict-concurrency error
    (`static property 'defaultValue' is not concurrency-safe`).
  - PASS (scratch compile): native `@Entry` with `fileprivate` and the
    non-Sendable wrapper-array default compiles clean under `-swift-version
    6` — its generated key dodges the stored-static error — and the entry is
    writable-keypath addressable. The expansion therefore delegates storage
    to `@Entry` instead of hand-rolling a key + accessor pair.
  - FAIL (probe macro): any generated *type* inside `extension View` (`type
    cannot be nested in protocol extension of 'View'`) and any generated
    `extension EnvironmentValues { … }` (`macro expansion cannot introduce
    extension`) — the rulings that killed the View-anchor shapes and forced
    this one.
- Resolved during implementation (compiled owners: `FlowUpSyntaxTests`
  expansion/diagnostics, `FlowUpTests` end-to-end):
  - PASS: fileprivate entry visibility from expansion buffers — the
    accessor, static, and tests all reach it.
  - PASS: trailing-closure inference of `Closure` at `.on(\.flow) { }`,
    plus combined-call order, same-signature isolation, throws-aborts,
    async-sequential, empty default, `.on`/`.accumulate` typechecking.
  - PASS: attributed `@MainActor (Int) -> Void` flow rides the whole
    pipeline and calls (after the `@unchecked Sendable` fix above).
  - FAIL: native `@Entry` inside our expansion — `'@Entry' macro can only
    attach to var declarations inside extensions of EnvironmentValues, …` —
    its container check cannot see the extension from another macro's
    expansion buffer. The hand-rolled entry is the shipped design; the
    CLAUDE.md attached-in-generated fact holds in general, but not for
    macros that inspect their lexical context.
- DECIDED — registration identity churn is fixed by `FlowUpRegistration`
  (stable wrapper in `@State`, payload refreshed each body; see Runtime).
  Two hosted checks own its remaining claims, in the example-app scenario:
  1. re-rendering a registering leaf N times never re-fires the accumulator
     or rewrites the environment (verifies the render-phase payload write is
     invisible to the dataflow);
  2. two chained `.on(\.same)` registrations on one view both survive. The
     registration modifier publishes via `transformPreference` (append)
     rather than `.preference` precisely so this holds under either nesting
     semantics — `.preference` SETS its node's value and may clobber an
     inner registration, while append composes through nesting and leaves
     sibling reduce untouched; for a lone registration it appends to the
     default `[]`, identical behavior. The hosted test locks it.
