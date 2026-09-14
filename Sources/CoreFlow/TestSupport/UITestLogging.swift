import SwiftUI

/// The log as an accessibility element for XCUITest: installs the sink and
/// exposes every `(name, value)` — names JSON in `label`, values JSON in
/// `value` — under `accessibilityIdentifier`. Always instruments; a hosted
/// test app applies it once at the root.
public extension View {
    func uiTestLog(accessibilityIdentifier: String) -> some View {
        modifier(UITestLogging(logIdentifier: accessibilityIdentifier))
    }
}

struct UITestLogging: ViewModifier {
    let logIdentifier: String

    /// A class, observed only by the leaf below: this body never reads the
    /// items, so an append re-renders the leaf and nothing else — no gate to
    /// rely on, and nothing for a SwiftUI build that does not shield a
    /// modifier's content to leak into the scenario.
    @Observable
    fileprivate final class Store {
        var items: [(String, String)] = []
    }

    @State private var store = Store()

    func body(content: Content) -> some View {
        content
            .background(Leaf(store: store, logIdentifier: logIdentifier))
            // Deferred: some events fire mid-render, and a synchronous append
            // there is a state write during a body evaluation.
            .testLog { property, value in
                Task { store.items.append((property, value)) }
            }
    }

    private struct Leaf: View {
        let store: Store
        let logIdentifier: String

        var body: some View {
            Color.clear
                .accessibilityElement()
                .accessibilityIdentifier(logIdentifier)
                .accessibilityLabel(Self.json(store.items.map(\.0)))
                .accessibilityValue(Self.json(store.items.map(\.1)))
        }

        private static func json(_ strings: [String]) -> String {
            String(decoding: try! JSONEncoder().encode(strings), as: UTF8.self)
        }
    }
}
