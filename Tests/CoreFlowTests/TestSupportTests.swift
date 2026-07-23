import CoreFlow
import SwiftUI
import Testing

// `\.testLog` is hardcoded to the package entry, whose default is a no-op —
// outside a live view @Environment reads that default, so the logging itself
// is verified live by the ExampleApp's UI snapshot tests. What's verifiable
// here: the generated surface compiles against real SwiftUI, bindings read
// their seeds, and action wrappers forward arguments, effects, and results.
private enum SaveProbe {
    nonisolated(unsafe) static var received: [String] = []
}

private struct CounterHost: View {
    @TestState var count: Int = 0
    @TestState var isOn = false
    @TestState var jump: () -> Void = {}
    @TestAction var save: (String) -> Void = { SaveProbe.received.append($0) }
    @TestAction var fetch: (Int) async throws -> [String] = { n in ["item\(n)"] }

    var body: some View { Color.clear }

    // Everything generated is private — a real host wires it all inside its
    // own body, so these drivers stand in for the body's wiring.
    func readCount() -> Int { $count.wrappedValue }
    func readIsOn() -> Bool { $isOn.wrappedValue }
    func writeCount(_ value: Int) { $count.wrappedValue = value }
    func swapJump(_ value: @escaping () -> Void) { $jump.wrappedValue = value }
    func callSave(_ value: String) { save(value) }
    func callFetch(_ n: Int) async throws -> [String] { try await fetch(n) }
}

// View conformance implies @MainActor isolation for the whole type, so the
// suite must match — same rule as OutFlowTests/ShellTests.
@MainActor
@Suite struct TestSupportEndToEndTests {

    @Test func stateBindingsReadTheirSeedsAndAcceptWrites() {
        let host = CounterHost()

        #expect(host.readCount() == 0)
        #expect(host.readIsOn() == false)

        // Writes log through \.testLog and land in State — a silent no-op
        // outside a live view, State's own behavior; a var closure is state
        // like any other, its binding swaps the closure itself.
        host.writeCount(5)
        host.swapJump {}
    }

    @Test func actionWrappersForwardArgumentsEffectsAndResults() async throws {
        SaveProbe.received = []
        let host = CounterHost()

        host.callSave("x")
        let items = try await host.callFetch(3)

        #expect(SaveProbe.received == ["x"])
        #expect(items == ["item3"])
    }
}
