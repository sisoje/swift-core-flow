import CoreFlow
import SwiftUI
import Testing

/// Internal + defaulted actions are defaulted memberwise parameters, so a
/// host is constructed with an observing closure; reading the property IS
/// the wrapped action, which forwards even with the log seam uninstalled.
private struct ActionHost: View {
    @TestAction var save: (String) -> Void = { _ in }
    @TestAction var refresh: () -> Bool = { true }
    @TestAction var fetch: @Sendable (Int) async throws -> Int = { $0 }

    var body: some View {
        Color.clear
    }
}

@MainActor
struct TestActionTests {
    @Test func actionsForwardToTheirStorage() async throws {
        var saved: [String] = []
        let host = ActionHost(save: { saved.append($0) })

        host.save("first")
        host.save("second")
        #expect(saved == ["first", "second"])
        #expect(host.refresh() == true)
        #expect(try await host.fetch(3) == 3)
    }
}
