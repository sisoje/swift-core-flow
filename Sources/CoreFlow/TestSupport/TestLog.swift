import SwiftUI

/// A struct, not a bare closure — a closure-typed `@Entry` warns that
/// dependents may invalidate on every update. The sink is `@MainActor`
/// (without it a `@Sendable async` action wrapper would call it off the main
/// actor — a data race for any sink touching @State) and takes `String`s, so
/// nothing non-Sendable rides through.
package struct TestLogSink {
    package var sink: @MainActor (_ name: String, _ value: String) -> Void

    package init(sink: @escaping @MainActor (_ name: String, _ value: String) -> Void = { _, _ in }) {
        self.sink = sink
    }
}

package extension EnvironmentValues {
    @Entry var testLog = TestLogSink()
}

/// The macros' generated log field (`private let log_x = TestLog()`) —
/// explicit because macro-generated `@Environment` sugar crashes swiftc
/// (see AGENTS.md); the hand-written sugar in here is fine, and nested
/// DynamicProperties install by type, so injection stays reactive.
@propertyWrapper
public struct TestLog: DynamicProperty {
    @Environment(\.testLog) private var entry

    public init() {}

    public var wrappedValue: @MainActor (_ name: String, _ value: String) -> Void {
        entry.sink
    }
}
