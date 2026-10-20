import XCTest

/// The XCUITest end of `View.uiTestLog(accessibilityIdentifier:)`: the
/// element it installs is the one with that identifier, any type; its
/// names (JSON in `label`) and values (JSON in `value`) decoded, and a wait
/// on any of its properties.
public extension XCUIElement {
    /// The logged names, decoded from the element's label; empty when the
    /// label is not a JSON string array.
    var logNames: [String] {
        Self.strings(label)
    }

    /// A `Text`'s content: its label on iOS and Mac Catalyst, its value on
    /// macOS.
    var text: String {
        #if os(macOS)
            value as? String ?? ""
        #else
            label
        #endif
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

    /// One spelling for every destination: on macOS `click()` can miss a
    /// button that a click at its centre hits, on Mac Catalyst `tap()` sends
    /// nothing, on an iPhone `click()` fails ("Pointer events are not
    /// supported for this device").
    func tapOrClick() {
        #if os(macOS)
            coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        #elseif targetEnvironment(macCatalyst)
            click()
        #else
            tap()
        #endif
    }

    private static func strings(_ json: String?) -> [String] {
        guard let json, let values = try? JSONDecoder().decode([String].self, from: Data(json.utf8))
        else { return [] }
        return values
    }
}

public extension XCUIApplication {
    /// A `Toggle`'s control: a checkbox on macOS, elsewhere the switch inside
    /// the labeled switch element.
    func toggle(_ identifier: String) -> XCUIElement {
        #if os(macOS)
            checkBoxes[identifier]
        #else
            switches[identifier].switches.firstMatch
        #endif
    }
}

public extension XCUICoordinate {
    /// The drag, under the same split as `tapOrClick()`.
    func pressOrClick(forDuration duration: TimeInterval, thenDragTo other: XCUICoordinate) {
        #if os(macOS) || targetEnvironment(macCatalyst)
            click(forDuration: duration, thenDragTo: other)
        #else
            press(forDuration: duration, thenDragTo: other)
        #endif
    }
}
