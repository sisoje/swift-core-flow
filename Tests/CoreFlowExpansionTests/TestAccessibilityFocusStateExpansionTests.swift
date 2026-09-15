@testable import CoreFlowMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class TestAccessibilityFocusStateExpansionTests: XCTestCase {
    let macros: [String: Macro.Type] = [
        "TestAccessibilityFocusState": TestAccessibilityFocusStateMacro.self,
    ]

    func testAccessibilityFocusStateExpansion() {
        // @TestFocusState's expansion over AccessibilityFocusState: computed
        // over a self-initialized REAL peer, the setter the one logging
        // point, `$a11yFocused` the real AccessibilityFocusState<T>.Binding
        // that .accessibilityFocused demands.
        assertMacroExpansion(
            """
            struct Host {
                @TestAccessibilityFocusState private var a11yFocused: Bool
            }
            """,
            expandedSource: """
            struct Host {
                private var a11yFocused: Bool {
                    get {
                        a11yFocused_storage.wrappedValue
                    }
                    nonmutating set {
                        log_a11yFocused.wrappedValue("a11yFocused", String(describing: newValue))
                        a11yFocused_storage.wrappedValue = newValue
                    }
                }

                private let a11yFocused_storage: AccessibilityFocusState<Bool> = AccessibilityFocusState()

                private let log_a11yFocused = TestLog()

                private var `$a11yFocused`: AccessibilityFocusState<Bool>.Binding {
                    a11yFocused_storage.projectedValue
                }
            }
            """,
            macros: macros
        )
    }
}
