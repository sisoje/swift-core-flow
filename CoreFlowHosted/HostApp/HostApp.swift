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

@main
struct CoreFlowHostApp: App {
    private let scenario: Scenario
    @State private var logItems: [(String, String)] = []

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
                case .queryViewSectionedLive: sectioned(mocked: false)
                case .queryViewSectionedMocked: sectioned(mocked: true)
                case .queryViewInsert: QueryViewInsertScenario()
                case .flowUp: FlowUpScenario()
                case .unstructuredTask: UnstructuredTaskScenario()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("log")
            .accessibilityLabel(json(logItems.map(\.0)))
            .accessibilityValue(json(logItems.map(\.1)))
            // Deferred (FIFO, order kept): some events arrive mid-render,
            // where a state write is undefined behavior.
            .testLog { property, value in
                DispatchQueue.main.async { logItems.append((property, value)) }
            }
        }
    }

    @ViewBuilder
    private func sectioned(mocked: Bool) -> some View {
        #if compiler(>=6.4)
            if #available(iOS 27.0, *) {
                QueryViewSectionedScenario(mocked: mocked)
            } else {
                Text("needs iOS 27")
            }
        #else
            Text("needs the 27 SDK")
        #endif
    }

    private func json(_ strings: [String]) -> String {
        String(decoding: try! JSONEncoder().encode(strings), as: UTF8.self)
    }
}
