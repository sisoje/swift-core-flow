import SwiftUI

/// The log as an accessibility element for XCUITest: installs the sink and
/// exposes every `(name, value)` on the content itself — names JSON in
/// `label`, values JSON in `value` — under `logIdentifier`. Always
/// instruments; a hosted test app applies it once at the root.
public extension View {
    func uiTestLog(accessibilityIdentifier: String) -> some View {
        modifier(UITestLogging(logIdentifier: accessibilityIdentifier))
    }
}

struct UITestLogging: ViewModifier {
    let logIdentifier: String
    /// An append re-renders this body only; `content` shields the scenario.
    @State private var items: [(String, String)] = []

    func body(content: Content) -> some View {
        Gate(content: content)
            .equatable()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(logIdentifier)
            .accessibilityLabel(Self.json(items.map(\.0)))
            .accessibilityValue(Self.json(items.map(\.1)))
            // Deferred: some events fire mid-render, and a synchronous
            // append there re-runs the scenario, not just this body.
            .testLog { property, value in
                Task { items.append((property, value)) }
            }
    }

    private static func json(_ strings: [String]) -> String {
        String(decoding: try! JSONEncoder().encode(strings), as: UTF8.self)
    }

    /// Always equal, so this body's re-render on every append never reaches
    /// `content` — a SwiftUI build that does not shield a modifier's content
    /// (27 beta 6) otherwise loops a scenario logging at render time.
    private struct Gate<Content: View>: View, @MainActor Equatable {
        static func == (_: Self, _: Self) -> Bool {
            true
        }

        let content: Content

        var body: some View {
            content
        }
    }
}
