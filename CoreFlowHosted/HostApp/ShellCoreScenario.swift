import CoreFlow
import SwiftUI

extension EnvironmentValues {
    @Entry var greeting = "default greeting"
}

@Shell
struct ShellCard: View {
    @State private var isOn = false
    @AppStorage("shellCardName") private var name = ""
    @Environment(\.greeting) private var greeting: String
    let title: String

    var body: some View {
        VStack {
            Text(title)
            Text(greeting)
            Button("toggle") { isOn.toggle() }
            Text(isOn ? "on" : "off")
            Button("rename") { name = "renamed" }
            Text(name.isEmpty ? "unnamed" : name)
        }
    }
}

/// The twin hosted: its `@State` logs as `@TestState`, its `@AppStorage`
/// writes through the supplied binding into the scenario's own `@TestState`,
/// and its verbatim `@Environment` reads the value mocked here.
struct ShellCoreScenario: View {
    @TestState private var name = ""

    var body: some View {
        ShellCard.Core(name: $name, title: "card")
            .environment(\.greeting, "mocked greeting")
    }
}

#Preview {
    ShellCoreScenario()
}
