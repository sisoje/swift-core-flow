import CoreFlowUITestShared
import XCTest

public extension XCUIApplication {
    static func launch(_ payload: some Encodable) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[UITestNames.launchPayloadEnvironmentVariable] = JsonUtils.encode(payload)
        app.launch()
        return app
    }
}
