import CoreFlow
import SwiftUI

// A component with an action AND a rest-api-looking async dependency: every
// tap fires the plain action, then fetches the user's name and writes it
// into its own @State. @Shell copies the body onto Core — the closures ride
// along as plain memberwise parameters, @State becomes @Binding.
@Shell
struct SaveButton: View {
    @State private var userName: String = ""
    let onSave: (String) -> Void
    let getUserName: (_ id: String) async throws -> String

    var body: some View {
        VStack(spacing: 16) {
            Text(userName.isEmpty ? "anonymous" : userName)
                .accessibilityIdentifier("userNameLabel")
            Button("Save Draft") {
                onSave("draft")
                Task {
                    userName = (try? await getUserName("42")) ?? "Error fetching user"
                }
            }
            .accessibilityIdentifier("saveDraftButton")
        }
    }
}

// Core component under test, everything logged at its own site, in order:
// the tap logs `onSave = draft` synchronously, the async wrapper logs
// `getUserName = 42` the moment the fetch is called (awaited in order, no
// fire-and-forget). The stub just throws — a mock needs no invented return
// value — so the component's own `?? "?"` fallback lands in state, logging
// `userName = ?` through the binding's setter: one deterministic three-line
// snapshot per tap, error path included.
struct SaveButtonScenario: View {
    @TestState var userName: String = ""
    @TestAction var onSave: (String) -> Void = { _ in }
    @TestAction var getUserName: @Sendable (_ id: String) async throws -> String = { _ in
        throw CancellationError()
    }

    var body: some View {
        SaveButton.Core(userName: $userName, onSave: onSave, getUserName: getUserName)
    }
}

#Preview {
    SaveButtonScenario()
}
