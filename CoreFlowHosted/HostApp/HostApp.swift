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

/// The log as a UIKit accessibility element whose label/value are computed
/// when XCUITest snapshots it: appends touch no SwiftUI state, so logging —
/// even mid-render — never re-renders anything.
final class LogBox {
    var items: [(String, String)] = []
}

final class LogView: UIView {
    let box: LogBox

    init(box: LogBox) {
        self.box = box
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityIdentifier = "log"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override var accessibilityLabel: String? {
        get { json(box.items.map(\.0)) }
        set {}
    }

    override var accessibilityValue: String? {
        get { json(box.items.map(\.1)) }
        set {}
    }

    private func json(_ strings: [String]) -> String {
        String(decoding: try! JSONEncoder().encode(strings), as: UTF8.self)
    }
}

struct LogElement: UIViewRepresentable {
    let box: LogBox

    func makeUIView(context _: Context) -> LogView {
        LogView(box: box)
    }

    func updateUIView(_: LogView, context _: Context) {}
}

@main
struct CoreFlowHostApp: App {
    private let scenario: Scenario
    private let box = LogBox()

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
            .background(LogElement(box: box))
            .testLog { property, value in box.items.append((property, value)) }
        }
    }

    @ViewBuilder
    private func sectioned(mocked: Bool) -> some View {
        #if canImport(SwiftData, _version: 180)
            if #available(iOS 27.0, *) {
                QueryViewSectionedScenario(mocked: mocked)
            } else {
                Text("needs iOS 27")
            }
        #else
            Text("needs the 27 SDK")
        #endif
    }
}
