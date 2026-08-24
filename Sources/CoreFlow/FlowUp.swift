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
    static var defaultValue: [FlowUpClosure<Closure>] {
        []
    }

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
        return
            content
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

public extension View {
    func onFlow<Tag, Closure>(
        _: KeyPath<EnvironmentValues.Type, FlowUpID<Tag, Closure>>,
        _ closure: Closure
    ) -> some View {
        modifier(FlowUpRegistration<Tag, Closure>(closure: closure))
    }

    func collectFlow<Tag, Closure>(
        _ id: KeyPath<EnvironmentValues.Type, FlowUpID<Tag, Closure>>
    ) -> some View {
        modifier(
            FlowUpAccumulator<Tag, Closure>(
                keyPath: EnvironmentValues.self[keyPath: id].keyPath
            )
        )
    }
}
