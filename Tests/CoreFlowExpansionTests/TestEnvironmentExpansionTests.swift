@testable import CoreFlowMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class TestEnvironmentExpansionTests: XCTestCase {
    let macros: [String: Macro.Type] = [
        "TestEnvironment": TestEnvironmentMacro.self,
    ]

    func testEnvironmentActionExpansion() {
        // @TestAction's wrapper closure over a REAL Environment peer: the
        // getter logs the name and the described arguments, then forwards to
        // whatever the environment holds — a sealed DismissAction, an
        // OpenURLAction, or a closure @Entry.
        assertMacroExpansion(
            """
            struct Host {
                @TestEnvironment(\\.dismiss) private var dismiss: () -> Void
                @TestEnvironment(\\.openURL) private var openURL: (URL) -> Void
            }
            """,
            expandedSource: """
            struct Host {
                private var dismiss: () -> Void {
                    get {
                        let log = log_dismiss.wrappedValue
                        let storage = dismiss_storage.wrappedValue
                        return {
                            log("dismiss", "")
                            storage()
                        }
                    }
                }

                private let dismiss_storage = Environment(\\.dismiss)

                private let log_dismiss = TestLog()
                private var openURL: (URL) -> Void {
                    get {
                        let log = log_openURL.wrappedValue
                        let storage = openURL_storage.wrappedValue
                        return { a0 in
                            log("openURL", String(describing: a0))
                            storage(a0)
                        }
                    }
                }

                private let openURL_storage = Environment(\\.openURL)

                private let log_openURL = TestLog()
            }
            """,
            macros: macros
        )
    }
}
