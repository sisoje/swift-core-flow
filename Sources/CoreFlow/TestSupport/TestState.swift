import SwiftUI

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
/// `static`, missing default or type — is a compile error at the attribute,
/// thrown by the macro itself; never a silent skip (a skipped shape can
/// compile as a plain, unmanaged stored property that never logs).
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
