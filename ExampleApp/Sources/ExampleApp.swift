import SwiftUI

// Which view (or group of views) this launch renders — selected via the
// EXAMPLE_SCENARIO environment variable (see UITests/LaunchHelper.swift for
// how it reaches the app under test, and testGestureState.sh/testFocusState.sh
// for how it reaches xcodebuild in the first place). One raw-value case per
// topic, not per view: GestureState covers both DragCard and TrickyDragCard,
// since both exercise the same wrapper.
enum ExampleScenario: String {
    case gestureState = "GestureState"
    case focusState = "FocusState"
    case viewModifier = "ViewModifier"

    /// Used when EXAMPLE_SCENARIO isn't set at all — running the app directly
    /// from Xcode (Cmd-R), with no scheme environment configured, rather than
    /// through one of the test*.sh scripts. Point this at whatever you're
    /// currently working on.
    static var defaultScenario: ExampleScenario { .focusState }
}

@main
struct ExampleApp: App {
    let scenario: ExampleScenario

    init() {
        guard let raw = ProcessInfo.processInfo.environment["EXAMPLE_SCENARIO"] else {
            // Not set at all — fine, use the default so Cmd-R from Xcode
            // just works with no setup.
            self.scenario = .defaultScenario
            return
        }
        // Set, but to something we don't recognize — that's a real mistake,
        // not the "ran with no config" case above, so it still crashes.
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
            case .focusState:
                FocusField()
            case .viewModifier:
                DimmerDemo()
            }
        }
    }
}
