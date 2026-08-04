import SwiftUI

/// A drop-in `@FocusState` that logs — attach to a stored `var` with a type
/// annotation (`Bool` or an optional, exactly the values `@FocusState`
/// itself accepts). The property becomes computed over a self-initialized
/// real `FocusState` peer, so hosted behavior is the live wrapper's own —
/// focus genuinely moves — while every programmatic write logs
/// `(name, newValue)` through `\.testLog` at the write site:
///
/// ```swift
/// struct LoginScenario: View {
///     @TestFocusState private var focus: Field?
///     var body: some View {
///         TextField("email", text: $email)
///             .focused($focus, equals: .email)   // $focus IS FocusState<Field?>.Binding
///         Button("next") { focus = .password }   // logs ("focus", "Optional(MyApp.Field.password)")
///                                                // — String(describing:) qualifies enum cases
///     }
/// }
/// ```
///
/// `$name` forwards the REAL `FocusState<T>.Binding` — `.focused(_:equals:)`
/// demands that exact nominal type, and it has no public initializer to
/// wrap — so writes through the binding (the SYSTEM moving focus on tap,
/// keyboard dismissal, …) deliberately don't log: scheduler-owned timing
/// has no place in a snapshot log. The property logs, the projection wires.
///
/// Like `@FocusState`, there is no inline default — focus starts at the
/// wrapper's own reset value (`false`/`nil`) — and the property is never a
/// memberwise-init parameter whatever its access level. The required shape
/// is a stored instance `var` with a type annotation and no initial value;
/// anything else is a compile error at the attribute, thrown by the macro
/// itself — never a silent skip. `$name` and every other
/// generated member is private — only the host's own `body` wires it.
/// Unhosted, writes no-op like the live wrapper's, reads keep returning
/// the reset value, and the setter's sink call reaches only `\.testLog`'s
/// no-op default — production-safe, logging costs nothing until a sink is
/// installed by a hosted `.testLog { }`.
@attached(accessor, names: named(get), named(set))
@attached(peer, names: prefixed(`$`), prefixed(log_), suffixed(_storage))
public macro TestFocusState() =
    #externalMacro(module: "CoreFlowMacros", type: "TestFocusStateMacro")
