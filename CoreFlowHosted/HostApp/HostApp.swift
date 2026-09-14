import CoreFlow
import SwiftUI

enum Scenario: String {
    case queryViewGated = "QueryViewGated"
    case queryViewUngated = "QueryViewUngated"
    case mockQueryResults = "MockQueryResults"
    case queryViewSectionedLive = "QueryViewSectionedLive"
    case queryViewSectionedMocked = "QueryViewSectionedMocked"
    case queryViewInsert = "QueryViewInsert"
    case flowUp = "FlowUp"
    case unstructuredTask = "UnstructuredTask"
}

/// Logging exists only under a launching test, which names the element
/// through `TEST_LOG`; Cmd-R and previews get the bare content.
struct TestLogging: ViewModifier {
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

extension View {
    func setupLogging(_ logIdentifier: String) -> some View {
        modifier(TestLogging(logIdentifier: logIdentifier))
    }
}

@main
struct CoreFlowHostApp: App {
    private let scenario: Scenario
    private let logIdentifier: String

    init() {
        guard let logIdentifier = ProcessInfo.processInfo.environment["TEST_LOG"] else {
            fatalError("TEST_LOG not set")
        }
        guard let raw = ProcessInfo.processInfo.environment["SCENARIO"] else {
            fatalError("SCENARIO not set")
        }
        guard let scenario = Scenario(rawValue: raw) else {
            fatalError("Unknown SCENARIO: \(raw)")
        }
        self.logIdentifier = logIdentifier
        self.scenario = scenario
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch scenario {
                case .queryViewGated: QueryViewSortScenario(gated: true)
                case .queryViewUngated: QueryViewSortScenario(gated: false)
                case .mockQueryResults: MockQueryResultsScenario()
                case .queryViewSectionedLive: QueryViewSectionedScenario(mocked: false)
                case .queryViewSectionedMocked: QueryViewSectionedScenario(mocked: true)
                case .queryViewInsert: QueryViewInsertScenario()
                case .flowUp: FlowUpScenario()
                case .unstructuredTask: UnstructuredTaskScenario()
                }
            }
            .setupLogging(logIdentifier)
        }
    }
}
