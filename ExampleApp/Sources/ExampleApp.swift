import SwiftUI

// Which view (or group of views) this launch renders — selected via the
// EXAMPLE_SCENARIO environment variable (see UITests/LaunchHelper.swift for
// how it reaches the app under test, and testGestureState.sh for how it
// reaches xcodebuild in the first place). One raw-value case per topic, not
// per view: GestureState covers both DragCard and TrickyDragCard, since both
// exercise the same wrapper.
enum ExampleScenario: String {
    case gestureState = "GestureState"
}

@main
struct ExampleApp: App {
    let scenario: ExampleScenario

    init() {
        // No scenario, no app — crash immediately rather than silently
        // rendering the wrong (or no) view.
        guard let raw = ProcessInfo.processInfo.environment["EXAMPLE_SCENARIO"] else {
            fatalError(
                "EXAMPLE_SCENARIO environment variable not set — this app doesn't know which example view to run."
            )
        }
        guard let scenario = ExampleScenario(rawValue: raw) else {
            fatalError("EXAMPLE_SCENARIO=\"\(raw)\" doesn't match any known scenario.")
        }
        self.scenario = scenario
    }

    var body: some Scene {
        WindowGroup {
            switch scenario {
            case .gestureState:
                VStack(spacing: 48) {
                    DragCard()
                    TrickyDragCard()
                }
            }
        }
    }
}
