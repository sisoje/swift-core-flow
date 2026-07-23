import SwiftUI

/// The mutation-log seam `@TestState`/`@TestAction` call: `(name, value
/// description)` for every logged write and call. A callable struct, not a
/// bare closure — a closure-typed `@Entry` warns that dependents may
/// invalidate on every update (closures aren't comparable); this wraps the
/// sink and compares always-equal, honest for a seam installed once at the
/// scene root. `callAsFunction` keeps call sites spelled like the closure
/// they replace. The sink is `@MainActor` (Sendable, serialized on the main
/// actor whatever context the logged action runs in) with `String` payloads,
/// so nothing non-Sendable rides through. The `@MainActor` on the sink is
/// load-bearing: without it a `@Sendable async` action wrapper calls the
/// sink off the main actor — a data race for any sink touching @State.
public struct ComparableLog: Equatable, Sendable {
    public init(sink: @escaping @MainActor (String, String) -> Void = { _, _ in }) {
        self.sink = sink
    }

    let sink: @MainActor (_ name: String, _ value: String) -> Void

    @MainActor
    public func callAsFunction(_ name: String, _ value: String) {
        sink(name, value)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    @Entry public var testLog = ComparableLog()
}

/// A drop-in `@State` that logs — attach to a defaulted stored `var`.
/// The property is rewritten to read/write a generated `State` storage, so it
/// stays LIVE exactly like `@State`'s own wrappedValue; the one logging call
/// sits in its setter, so every write logs `(name, newValue)` through
/// `\.testLog` at the write site — direct writes and `$name` binding writes
/// alike:
///
/// ```swift
/// struct CounterScenario: View {
///     @TestState var count: Int = 0    // live count + $count: Binding<Int>
///     var body: some View { CoreView(count: $count) }
/// }
/// ```
///
/// Works on a `var` of ANY type, function types included (a `var` closure
/// means someone wants to mutate the closure itself, and the binding is
/// exactly that). The type comes from the annotation or a bare
/// `Bool`/`Int`/`String` literal default. Anything else — `let`, computed,
/// `static`, missing default — is skipped without diagnostics; the use site
/// expecting `$name` fails in the compiler's own words.
///
/// `$name` and every other generated member is private — only the host's own
/// `body` wires them. Keep the property itself internal: `private` would drag
/// Swift's memberwise init down to `private` too, forcing a hand-written
/// `init() {}` (the generated peers don't — the storage is subsumed by the
/// init accessor and `log_x` has a default, so neither becomes a parameter).
/// Outside a live view, `\.testLog` reads its no-op default — logging is
/// verified where a real render installs the sink.
@attached(accessor, names: named(init), named(get), named(set))
@attached(peer, names: prefixed(`$`), prefixed(log_), suffixed(_storage))
public macro TestState() =
    #externalMacro(module: "CoreFlowMacros", type: "TestStateMacro")

/// Logged action for a test host, per property. Attach to a stored `var`
/// closure; the property's own getter returns the stored closure wrapped with
/// logging — reading `save` IS the logged action, nothing extra to wire. Each
/// call logs `(name, payload)` through `\.testLog` the moment it fires, then
/// forwards — payload `""` for zero arguments, the described bare argument for
/// one, a described tuple beyond; `async`/`throws`/return value carried
/// through (`return try await`):
///
/// ```swift
/// struct SaveScenario: View {
///     @TestAction var save: (Item) -> Void = { _ in }
///     var body: some View { CoreView(onSave: save) }
/// }
/// ```
///
/// Closures only, and `var` — the compiler refuses accessor expansion on
/// `let`; anything else is skipped. No setter: an action is wired, not
/// mutated.
@attached(accessor, names: named(init), named(get))
@attached(peer, names: prefixed(log_), suffixed(_storage))
public macro TestAction() =
    #externalMacro(module: "CoreFlowMacros", type: "TestActionMacro")
