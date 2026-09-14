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

    /// Used when `SCENARIO` is unset, so Cmd-R just works.
    static var defaultScenario: Scenario {
        .queryViewGated
    }
}

/// Logging exists only under a launching test, which names the element
/// through `TEST_LOG`; Cmd-R and previews get the bare content.
struct TestLogging: ViewModifier {
    /// An append re-renders this body only; `content` shields the scenario.
    @State private var items: [(String, String)] = []

    func body(content: Content) -> some View {
        if let name = ProcessInfo.processInfo.environment["TEST_LOG"] {
            content
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(name)
                .accessibilityLabel(json(items.map(\.0)))
                .accessibilityValue(json(items.map(\.1)))
                // Deferred: some events fire mid-render, and a synchronous
                // append there re-runs the scenario, not just this body.
                .testLog { name, value in
                    Task { items.append((name, value)) }
                }
        } else {
            content
        }
    }

    private func json(_ strings: [String]) -> String {
        String(decoding: try! JSONEncoder().encode(strings), as: UTF8.self)
    }
}

extension View {
    func setupLogging() -> some View {
        modifier(TestLogging())
    }
}

@main
struct CoreFlowHostApp: App {
    private let scenario: Scenario

    init() {
        guard let raw = ProcessInfo.processInfo.environment["SCENARIO"] else {
            scenario = .defaultScenario
            return
        }
        guard let scenario = Scenario(rawValue: raw) else {
            fatalError("Unknown SCENARIO: \(raw)")
        }
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
            .setupLogging()
        }
    }
}
