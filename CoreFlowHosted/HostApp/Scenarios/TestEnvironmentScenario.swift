import CoreFlow
import SwiftUI

/// A sheet's own close button. `@Environment(\.dismiss)` on the host is
/// `@TestEnvironment(\.dismiss)` on `Core`: the call logs, then the REAL
/// action runs and the sheet closes.
@Shell
struct SheetContent: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("close") { dismiss() }
    }
}

struct TestEnvironmentScenario: View {
    @TestState private var isPresented = false

    var body: some View {
        Button("present") { isPresented = true }
            .sheet(isPresented: $isPresented) { SheetContent.Core() }
    }
}

#Preview {
    TestEnvironmentScenario()
}
