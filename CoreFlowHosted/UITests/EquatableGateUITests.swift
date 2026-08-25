import XCTest

final class EquatableGateUITests: XCTestCase {
    @MainActor
    func testEquatableSkipsUnchangedBodiesOnUnrelatedRenders() {
        let app = launchApp(scenario: "EquatableGate")
        XCTAssertTrue(app.buttons["unrelated"].waitForExistence(timeout: 5))
        for _ in 1 ... 3 {
            app.buttons["unrelated"].tap()
        }

        // Observed on 27A5252f: both gates run at launch, both run once more
        // on the FIRST parent re-render, then neither runs again — isolated
        // and nonisolated conformances behave identically. The probe exists
        // to see whether a beta separates them.
        let names = #"["isolated","nonisolated","unrelated","isolated","nonisolated","unrelated","unrelated"]"#
        XCTAssertTrue(app.log.wait(for: \.label, toEqual: names, timeout: 5), app.log.label)
    }
}
