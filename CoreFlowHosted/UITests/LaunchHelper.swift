import XCTest

/// The app is a separate process and inherits nothing from the shell that
/// invoked xcodebuild, so every test hands it a `TestPayload`.
@MainActor
func launchApp(scenario: TestScenario) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment[TestPayload.testPayloadEnvironmentKey] = TestPayload(scenario: scenario).encoded
    app.launch()
    return app
}

extension XCUIApplication {
    var log: XCUIElement {
        otherElements[TestPayload.logAccessibilityIdentifier]
    }

    /// The log's values, JSON-decoded from the element's value; empty when
    /// the value is missing or undecodable.
    var logValues: [String] {
        guard let raw = log.value as? String,
              let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return values
    }
}

extension XCUIElement {
    @discardableResult
    func wait<Value: Equatable>(
        for keyPath: KeyPath<XCUIElement, Value>,
        toEqual expected: Value,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { element, _ in
                guard let element = element as? XCUIElement else { return false }
                return element[keyPath: keyPath] == expected
            },
            object: self
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
