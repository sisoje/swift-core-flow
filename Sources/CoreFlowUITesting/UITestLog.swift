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

    /// Reads the property at `keyPath` until it equals `expected`; `false` on
    /// timeout. Returns the moment it matches, with no interval between reads
    /// (each one is a query to the app). XCTest's own
    /// `wait(for:toEqual:timeout:)` and `waitForExistence(timeout:)` wait
    /// about a second before their first check; a method here named like
    /// either would be shadowed by XCTest's. The names assertion of a
    /// scenario is `waitUntil(\.label, equals: #"["count","isOn"]"#,
    /// timeout: 5)`: names are fixed identifiers, so the raw JSON string
    /// compares exactly.
    @discardableResult
    func waitUntil<Value: Equatable>(
        _ keyPath: KeyPath<XCUIElement, Value>,
        equals expected: Value,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while self[keyPath: keyPath] != expected {
            if Date() >= deadline {
                return false
            }
        }
        return true
    }

    private static func strings(_ json: String?) -> [String] {
        guard let json, let values = try? JSONDecoder().decode([String].self, from: Data(json.utf8))
        else { return [] }
        return values
    }
}
