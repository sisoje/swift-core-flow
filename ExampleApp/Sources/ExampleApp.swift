import CoreFlow
import SwiftUI

// Which Core component this launch hosts — selected via the
// EXAMPLE_SCENARIO environment variable (see UITests/SnapshotTestCase.swift
// for how it reaches the app under test). One case per component, flat.
enum ExampleScenario: String {
    case dragCard = "DragCard"
    case trickyDragCard = "TrickyDragCard"
    case focusField = "FocusField"
    case dimmer = "Dimmer"
    case saveButton = "SaveButton"

    /// Used when EXAMPLE_SCENARIO isn't set — running from Xcode (Cmd-R).
    static var defaultScenario: ExampleScenario { .focusField }
}

@main
struct ExampleApp: App {
    let scenario: ExampleScenario

    /// Everything logged, in order — exposed on the `log` element below.
    @State private var logItems: [(String, String)] = []
    var logNamesJSON: String { json(logItems.map(\.0)) }
    var logValuesJSON: String { json(logItems.map(\.1)) }

    private func json(_ items: [String]) -> String {
        String(data: try! JSONEncoder().encode(items), encoding: .utf8)!
    }

    init() {
        guard let raw = ProcessInfo.processInfo.environment["EXAMPLE_SCENARIO"] else {
            self.scenario = .defaultScenario
            return
        }
        guard let scenario = ExampleScenario(rawValue: raw) else {
            fatalError("EXAMPLE_SCENARIO=\"\(raw)\" doesn't match any known scenario.")
        }
        self.scenario = scenario
    }

    var testLog: @MainActor (String, String) -> Void {
        { property, value in
            logItems.append((property, value))
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch scenario {
                case .dragCard: DragCardScenario()
                case .trickyDragCard: TrickyDragCardScenario()
                case .focusField: FocusFieldScenario()
                case .dimmer: DimmerScenario()
                case .saveButton: SaveButtonScenario()
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
}
