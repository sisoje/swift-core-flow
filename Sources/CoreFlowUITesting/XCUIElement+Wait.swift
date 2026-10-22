import XCTest

public extension XCUIElement {
    /// No interval: each read is a query to the app. Not named like XCTest's
    /// `wait(for:toEqual:timeout:)`, which would shadow it and waits about a
    /// second before its first check.
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
}
