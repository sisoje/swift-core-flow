import CoreFlow
import SwiftUI

@testable import ReadingListUI

// Which Core component this launch hosts — selected via the SCENARIO
// environment variable (see UITests/LaunchHelper.swift). One case per
// component, flat.
enum Scenario: String {
    case bookRow = "BookRow"
    case bookList = "BookList"
    case addBook = "AddBook"

    /// Used when SCENARIO isn't set — running from Xcode (Cmd-R).
    static var defaultScenario: Scenario { .bookList }
}

@main
struct ReadingListTestApp: App {
    let scenario: Scenario

    /// Everything logged, in order — exposed on the `log` element below.
    @State private var logItems: [(String, String)] = []

    init() {
        guard let raw = ProcessInfo.processInfo.environment["SCENARIO"] else {
            self.scenario = .defaultScenario
            return
        }
        guard let scenario = Scenario(rawValue: raw) else {
            fatalError("SCENARIO=\"\(raw)\" doesn't match any known scenario.")
        }
        self.scenario = scenario
    }

    var testLog: ComparableLog {
        ComparableLog { property, value in
            logItems.append((property, value))
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch scenario {
                case .bookRow: BookRowScenario()
                case .bookList: BookListScenario()
                case .addBook: AddBookScenario()
                }
            }
            // Names in label, values in value — JSON, read by UI tests.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("log")
            .accessibilityLabel(logNamesJSON)
            .accessibilityValue(logValuesJSON)
        }
        .environment(\.testLog, testLog)
    }

    var logNamesJSON: String { json(logItems.map(\.0)) }
    var logValuesJSON: String { json(logItems.map(\.1)) }

    private func json(_ items: [String]) -> String {
        String(data: try! JSONEncoder().encode(items), encoding: .utf8)!
    }
}
