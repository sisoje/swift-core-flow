import SwiftUI

/// A logged call through a real environment value — attach to a stored `var`
/// with a function-type annotation and no initial value, naming the key path:
///
/// ```swift
/// @TestEnvironment(\.dismiss) private var dismiss: () -> Void
/// @TestEnvironment(\.openURL) private var openURL: (URL) -> Void
/// ```
///
/// Reading the property returns a closure that logs `(name, payload)` through
/// `\.testLog` — `""` for zero arguments, the described argument for one, a
/// described tuple beyond, `try`/`await` carried through — and then calls the
/// REAL value read from `Environment(\.keyPath)`. A live instrument, not a
/// mock: hosted, `dismiss()` logs `dismiss` and the sheet closes; unhosted, the
/// environment's default runs, a no-op for these sealed actions. Your own
/// closure `@Entry` needs none of this: inject it with `.environment`. A
/// labeled action such as `openWindow(id:)` has no closure spelling. `@Shell` substitutes this for a private
/// `@Environment` on its key-path whitelist (`\.dismiss`, `\.openURL`).
@attached(accessor, names: named(get))
@attached(peer, names: prefixed(log_), suffixed(_storage))
public macro TestEnvironment<Value>(_ keyPath: KeyPath<EnvironmentValues, Value>) =
    #externalMacro(module: "CoreFlowMacros", type: "TestEnvironmentMacro")
