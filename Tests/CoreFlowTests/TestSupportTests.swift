import CoreFlow
import SwiftUI
import Testing

// `\.testLog` is hardcoded to the package entry, whose default is a no-op.
// Setter writes and action calls read that seam — an @Environment read
// SwiftUI flags as a runtime issue outside a live view — so logging and
// forwarding are verified live by CoreFlowExample's UI tests. Verifiable
// here: the generated surface compiles against real SwiftUI and bindings
// read their seeds.
private struct CounterHost: View {
    @TestState var count: Int = 0
    @TestState var isOn = false

    var body: some View {
        Color.clear
    }

    /// Everything generated is private — a real host wires it all inside its
    /// own body, so these drivers stand in for the body's wiring.
    func readCount() -> Int {
        $count.wrappedValue
    }

    func readIsOn() -> Bool {
        $isOn.wrappedValue
    }
}

/// View conformance implies @MainActor isolation for the whole type, so the
/// suite must match — same rule as ShellTests.
@MainActor
struct TestSupportEndToEndTests {
    @Test func stateBindingsReadTheirSeeds() {
        let host = CounterHost()

        #expect(host.readCount() == 0)
        #expect(host.readIsOn() == false)
    }
}
