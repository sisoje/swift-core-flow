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

/// XCUITest reads label/value on demand, so appending re-renders nothing —
/// even from inside a body.
final class LogView: UIView {
    var items: [(String, String)] = []

    override var accessibilityLabel: String? {
        get { Self.json(items.map(\.0)) }
        set {}
    }

    override var accessibilityValue: String? {
        get { Self.json(items.map(\.1)) }
        set {}
    }

    private static func json(_ strings: [String]) -> String {
        String(decoding: try! JSONEncoder().encode(strings), as: UTF8.self)
    }
}

struct LogElement: UIViewRepresentable {
    let log: LogView

    func makeUIView(context _: Context) -> LogView {
        log.isAccessibilityElement = true
        log.accessibilityIdentifier = "log"
        return log
    }

    func updateUIView(_: LogView, context _: Context) {}
}

@main
struct CoreFlowHostApp: App {
    private let scenario: Scenario
    private let log = LogView()

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
            .background(LogElement(log: log))
            .testLog { log.items.append(($0, $1)) }
        }
    }
}
