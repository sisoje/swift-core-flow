import XCTest

/// The XCUITest end of `View.uiTestLog(accessibilityIdentifier:)`: the
/// element it installs, its names (JSON in `label`) and values (JSON in
/// `value`) decoded, and a wait on any of its properties.
public extension XCUIApplication {
    func uiTestLog(accessibilityIdentifier: String) -> XCUIElement {
        otherElements[accessibilityIdentifier]
    }
}

public extension XCUIElement {
    /// The logged names, decoded from the element's label; empty when the
    /// label is not a JSON string array.
    var logNames: [String] {
        Self.strings(label)
    }

    /// The logged values, decoded from the element's value; empty when the
    /// value is not a JSON string array.
    var logValues: [String] {
        Self.strings(value as? String)
    }

    /// Polls until the property at `keyPath` equals `expected`; `false` on
    /// timeout. The names assertion of a scenario is
    /// `wait(for: \.label, toEqual: #"["count","isOn"]"#, timeout: 5)`:
    /// names are fixed identifiers, so the raw JSON string compares exactly.
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

    private static func strings(_ json: String?) -> [String] {
        guard let json, let values = try? JSONDecoder().decode([String].self, from: Data(json.utf8))
        else { return [] }
        return values
    }
}
