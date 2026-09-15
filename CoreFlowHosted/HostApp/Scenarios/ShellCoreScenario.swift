import CoreFlow
import SwiftData
import SwiftUI

extension EnvironmentValues {
    @Entry var greeting = "default greeting"
}

/// Every substitution row on one host: `@State`, `@FocusState`,
/// `@AppStorage`, `@Query`, plus a verbatim `@Environment`.
@Shell
struct ShellCard: View {
    @State private var isOn = false
    @FocusState private var isFocused: Bool
    @AppStorage("shellCardName") private var name = ""
    @Query private var novels: [Novel]
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
            TextField("field", text: .constant(""))
                .focused($isFocused)
            Button("focus") { isFocused = true }
            ForEach(novels) { Text($0.title) }
        }
    }
}

/// The twin hosted: `@State`/`@FocusState` log as their test twins, the
/// `@AppStorage` row writes through the supplied binding into the scenario's
/// own `@TestState`, the `@Query` row is a bare array, and the verbatim
/// `@Environment` reads the value mocked here.
struct ShellCoreScenario: View {
    @TestState private var name = ""

    var body: some View {
        ShellCard.Core(
            name: $name,
            novels: [Novel(title: "Dune", genre: "Sci-Fi")],
            title: "card"
        )
        .environment(\.greeting, "mocked greeting")
    }
}

#Preview {
    ShellCoreScenario()
}
