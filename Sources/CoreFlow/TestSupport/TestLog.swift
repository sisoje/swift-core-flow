import SwiftUI

/// A struct, not a bare closure — a closure-typed `@Entry` warns that
/// dependents may invalidate on every update; always-equal is honest for a
/// seam installed once. The sink is `@MainActor` (without it a `@Sendable
/// async` action wrapper would call it off the main actor — a data race for
/// any sink touching @State) and takes `String`s, so nothing non-Sendable
/// rides through.
struct ComparableLog: Equatable {
    var sink: @MainActor (_ name: String, _ value: String) -> Void = { _, _ in }

    static func == (_: Self, _: Self) -> Bool {
        true
    }
}

extension EnvironmentValues {
    @Entry var testLog = ComparableLog()
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

public extension View {
    func testLog(
        _ sink: @escaping @MainActor (_ name: String, _ value: String) -> Void
    ) -> some View {
        environment(\.testLog, ComparableLog(sink: sink))
    }
}
