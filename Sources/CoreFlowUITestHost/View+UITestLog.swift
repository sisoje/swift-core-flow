import CoreFlow
import CoreFlowUITestShared
import SwiftUI

public extension View {
    func uiTestLog() -> some View {
        modifier(UITestLog())
    }
}

struct UITestLog: ViewModifier {
    /// Observed only by the log element: an append re-renders it and nothing else.
    @Observable
    fileprivate final class Store {
        var items: [(String, String)] = []
    }

    @State private var store = Store()

    func body(content: Content) -> some View {
        content
            .background(LogElement(store: store))
            .environment(\.testLog, TestLogSink { property, value in
                store.items.append((property, value))
            })
    }

    private struct LogElement: View {
        let store: Store

        // On macOS an element of any other role has no value; on UIKit the
        // trait empties an empty log's label.
        #if os(macOS)
            private static let traits: AccessibilityTraits = .isStaticText
        #else
            private static let traits: AccessibilityTraits = []
        #endif

        var body: some View {
            Color.clear
                .accessibilityElement()
                .accessibilityAddTraits(Self.traits)
                .accessibilityIdentifier(UITestNames.logElementAccessibilityIdentifier)
                .accessibilityLabel(JsonUtils.encode(store.items.map(\.0)))
                .accessibilityValue(JsonUtils.encode(store.items.map(\.1)))
        }
    }
}
