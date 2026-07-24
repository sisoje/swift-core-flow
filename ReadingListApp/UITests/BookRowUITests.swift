import XCTest

final class BookRowUITests: XCTestCase {
    // The star writes through Core's @Binding into the scenario's @TestState —
    // both taps logged at the write site, in order.
    @MainActor
    func testFavoriteTogglesAndLogsEachWrite() {
        let app = launchApp(scenario: "BookRow")

        let star = app.buttons["favoriteButton"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        XCTAssertEqual(star.label, "☆")

        star.tap()
        XCTAssertTrue(star.wait(for: \.label, toEqual: "★", timeout: 5))

        star.tap()
        XCTAssertTrue(star.wait(for: \.label, toEqual: "☆", timeout: 5))

        XCTAssertTrue(
            app.log.wait(for: \.label, toEqual: #"["isFavorite","isFavorite"]"#, timeout: 5))
        XCTAssertEqual(app.logValues, ["true", "false"])
    }
}
