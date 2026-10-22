import CoreFlowUITestShared
import XCTest

public extension XCUIApplication {
    var logElement: XCUIElement {
        descendants(matching: .any)[UITestNames.logElementAccessibilityIdentifier]
    }
}

public extension XCUIElement {
    var logNames: [String] {
        JsonUtils.decode(label)
    }

    var logValues: [String] {
        (value as? String).map(JsonUtils.decode) ?? []
    }
}
