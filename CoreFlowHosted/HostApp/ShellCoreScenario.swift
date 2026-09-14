import CoreFlow
import SwiftUI

@Shell
struct ShellCard: View {
    @State private var isOn = false
    @AppStorage("shellCardName") private var name = ""
    let title: String

    var body: some View {
        VStack {
            Text(title)
            Button("toggle") { isOn.toggle() }
            Text(isOn ? "on" : "off")
            Button("rename") { name = "renamed" }
            Text(name.isEmpty ? "unnamed" : name)
        }
    }
}

/// The twin hosted: its `@State` logs as `@TestState`, its `@AppStorage`
/// writes through the supplied binding into the scenario's own `@TestState`.
struct ShellCoreScenario: View {
    @TestState private var name = ""

    var body: some View {
        ShellCard.Core(name: $name, title: "card")
    }
}

#Preview {
    ShellCoreScenario()
}
