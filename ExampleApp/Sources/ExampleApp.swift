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

    /// The one sink every @TestHost scenario reports through — appends each
    /// mutation as a `name = value` line the moment it happens. CoreFlow's
    /// `\.testLog` entry defaults to a no-op, so plain runs (Cmd-R,
    /// non-snapshot tests) log nothing.
    var testLog: @MainActor (String, String) -> Void {
        guard let path = ProcessInfo.processInfo.environment["SNAPSHOT_LOG"] else {
            return { _, _ in }
        }
        let url = URL(fileURLWithPath: path)
        return { property, value in
            try! url.append("\(property) = \(value)")
        }
    }

    var body: some Scene {
        WindowGroup {
            switch scenario {
            case .dragCard: DragCardScenario()
            case .trickyDragCard: TrickyDragCardScenario()
            case .focusField: FocusFieldScenario()
            case .dimmer: DimmerScenario()
            case .saveButton: SaveButtonScenario()
            }
        }
        .environment(\.testLog, testLog)
    }
}
