import SwiftUI

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
/// Closures only, `var` only, defaulted only — anything else is a compile
/// error at the attribute, thrown by the macro itself; never a silent
/// skip. No setter: an action is wired, not mutated.
@attached(accessor, names: named(init), named(get))
@attached(peer, names: prefixed(log_), suffixed(_storage))
public macro TestAction() =
    #externalMacro(module: "CoreFlowMacros", type: "TestActionMacro")
