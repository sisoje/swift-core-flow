import SwiftUI

/// A struct, not a bare closure — a closure-typed `@Entry` warns that
/// dependents may invalidate on every update; always-equal is honest for a
/// seam installed once. The sink is `@MainActor` (without it a `@Sendable
/// async` action wrapper would call it off the main actor — a data race for
/// any sink touching @State) and takes `String`s, so nothing non-Sendable
/// rides through.
struct ComparableLog: Equatable {
    var sink: @MainActor (_ name: String, _ value: String) -> Void = { _, _ in }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var testLog = ComparableLog()
}

/// The macros' generated log field (`private let log_x = TestLog()`) —
/// explicit because macro-generated `@Environment` sugar crashes swiftc
/// (see CLAUDE.md); the hand-written sugar in here is fine, and nested
/// DynamicProperties install by type, so injection stays reactive.
@propertyWrapper
public struct TestLog: DynamicProperty {
    @Environment(\.testLog) private var entry

    public init() {}

    public var wrappedValue: @MainActor (_ name: String, _ value: String) -> Void {
        entry.sink
    }
}

extension View {
    public func testLog(
        _ sink: @escaping @MainActor (_ name: String, _ value: String) -> Void
    ) -> some View {
        environment(\.testLog, ComparableLog(sink: sink))
    }
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
/// `body` wires them. The property's own access picks its role: internal +
/// defaulted → a defaulted memberwise-init parameter (a scenario host
/// constructs bare); private + defaulted → excluded from the memberwise
/// init entirely, a sealed source of truth that logs (what `@Shell`
/// generates on `Core` — verified directly, the init stays internal; the
/// generated peers never become parameters either way — the storage is
/// subsumed by the init accessor and `log_x` has a default).
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
