import SwiftUI

/// `@FlowUp var handleUrl: (URL) async throws -> Void` — one line inside
/// your own `extension EnvironmentValues` declares an upward closure flow:
/// `.onFlow(\.handleUrl) { url in … }` registers a listener, an ancestor's
/// `.collectFlow(\.handleUrl)` collects every listener below it into the
/// environment, and `@Environment(\.handleUrl)` reads one combined closure
/// calling them all in order.
@attached(accessor)
@attached(peer, names: arbitrary)
public macro FlowUp() =
    #externalMacro(module: "CoreFlowMacros", type: "FlowUpMacro")

public final class _FlowUpClosure<Closure>: Equatable, @unchecked Sendable {
    public internal(set) var closures: [Closure] = []

    public init() {}

    public static func == (lhs: _FlowUpClosure, rhs: _FlowUpClosure) -> Bool {
        lhs === rhs
    }
}

/// One per collector, the same object in the environment for the collector's
/// whole life. The flow's closure reads `wrappers` when it is called, so a
/// closure held longer than one pass still reaches the current listeners.
public final class _FlowUpCaller<Closure>: Equatable, @unchecked Sendable {
    public internal(set) var wrappers: [_FlowUpClosure<Closure>] = []

    public init() {}

    public static func == (lhs: _FlowUpCaller, rhs: _FlowUpCaller) -> Bool {
        lhs === rhs
    }
}

public struct _FlowUpID<Tag, Closure> {
    let keyPath: WritableKeyPath<EnvironmentValues, _FlowUpCaller<Closure>>

    public init(keyPath: WritableKeyPath<EnvironmentValues, _FlowUpCaller<Closure>>) {
        self.keyPath = keyPath
    }
}

struct FlowUpPreferenceKey<Tag, Closure>: PreferenceKey {
    static var defaultValue: [_FlowUpClosure<Closure>] {
        []
    }

    static func reduce(
        value: inout [_FlowUpClosure<Closure>],
        nextValue: () -> [_FlowUpClosure<Closure>]
    ) {
        value += nextValue()
    }
}

struct FlowUpRegistration<Tag, Closure>: ViewModifier {
    let closure: Closure

    @State private var wrapper = _FlowUpClosure<Closure>()

    func body(content: Content) -> some View {
        wrapper.closures = [closure]
        return
            content
                .transformPreference(FlowUpPreferenceKey<Tag, Closure>.self) { value in
                    value.append(wrapper)
                }
    }
}

struct FlowUpAccumulator<Tag, Closure>: ViewModifier {
    let keyPath: WritableKeyPath<EnvironmentValues, _FlowUpCaller<Closure>>

    @State private var caller = _FlowUpCaller<Closure>()

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(FlowUpPreferenceKey<Tag, Closure>.self) { [caller] listeners in
                caller.wrappers = listeners
            }
            .environment(keyPath, caller)
    }
}

public extension View {
    func onFlow<Tag, Closure>(
        _: KeyPath<EnvironmentValues.Type, _FlowUpID<Tag, Closure>>,
        _ closure: Closure
    ) -> some View {
        modifier(FlowUpRegistration<Tag, Closure>(closure: closure))
    }

    func collectFlow<Tag, Closure>(
        _ id: KeyPath<EnvironmentValues.Type, _FlowUpID<Tag, Closure>>
    ) -> some View {
        modifier(
            FlowUpAccumulator<Tag, Closure>(
                keyPath: EnvironmentValues.self[keyPath: id].keyPath
            )
        )
    }
}
