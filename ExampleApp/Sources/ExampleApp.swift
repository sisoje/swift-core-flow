import SwiftUI

// Which Core component this launch hosts — selected via the
// EXAMPLE_SCENARIO environment variable (see UITests/SnapshotTestCase.swift
// for how it reaches the app under test). One case per component, flat.
enum ExampleScenario: String {
    case dragCard = "DragCard"
    case trickyDragCard = "TrickyDragCard"
    case focusField = "FocusField"
    case dimmer = "Dimmer"

    /// Used when EXAMPLE_SCENARIO isn't set — running from Xcode (Cmd-R).
    static var defaultScenario: ExampleScenario { .focusField }
}

/// Injected once from the App scene; scenarios call it from a binding's
/// `didSet` so every mutation is logged the moment it happens. The default
/// is a no-op — plain runs (Cmd-R, non-snapshot tests) log nothing.
struct Logger {
    var mylog: (String, Any) -> Void = { _, _ in }
}

extension EnvironmentValues {
    @Entry var mylog: Logger = .init()
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

    var logger: Logger {
        guard let path = ProcessInfo.processInfo.environment["SNAPSHOT_LOG"] else {
            return Logger()
        }
        let url = URL(fileURLWithPath: path)
        return Logger { property, value in
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
            }
        }
        .environment(\.mylog, logger)
    }
}
