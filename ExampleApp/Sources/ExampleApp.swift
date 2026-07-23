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

    /// The NAMES of everything logged, in order — rendered into the hidden
    /// `logNames` element below so a UI test has a finish line: wait until
    /// the element reads exactly the expected comma-separated sequence, then
    /// let the snapshot diff verify the values.
    @State private var logItems: [(String, String)] = []
    var logNames: [String] { logItems.map(\.0) }

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

    /// The one sink every scenario reports through: always accumulates the
    /// logged NAME into the hidden `logNames` element (the UI test's finish
    /// line), and appends the full `name = value` line to the snapshot file
    /// when a test passed one via SNAPSHOT_LOG.
    var testLog: @MainActor (String, String) -> Void {
        { property, value in
            logItems.append((property, value))
            guard let path = ProcessInfo.processInfo.environment["SNAPSHOT_LOG"] else { return }
            try! URL(fileURLWithPath: path).append("\(property) = \(value)")
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
            // No phantom view: the payload rides on the container element
            // itself — identifier to find it, value to read it (that's what
            // the accessibility pair is for; XCUITest reads it as `.value`).
            // `.contain` keeps every child fully accessible.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("logNames")
            .accessibilityValue(logNames.joined(separator: ","))
        }
        .environment(\.testLog, testLog)
    }
}
