@testable import CoreFlowMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class TestFocusStateExpansionTests: XCTestCase {
    let macros: [String: Macro.Type] = [
        "TestState": TestStateMacro.self,
        "TestAction": TestActionMacro.self,
        "TestFocusState": TestFocusStateMacro.self,
    ]

    func testFocusStateExpansion() {
        // Computed over a self-initialized REAL FocusState peer — no init
        // accessor (@FocusState never carries a default, so there's nothing
        // to funnel; the property is never a memberwise parameter). `$focus`
        // forwards the real FocusState<T>.Binding — .focused demands that
        // exact nominal type — so binding writes (the system moving focus)
        // deliberately bypass the log; the one logging point is the setter.
        assertMacroExpansion(
            """
            struct Host {
                @TestFocusState private var focus: Field?
            }
            """,
            expandedSource: """
            struct Host {
                private var focus: Field? {
                    get {
                        focus_storage.wrappedValue
                    }
                    nonmutating set {
                        log_focus.wrappedValue("focus", String(describing: newValue))
                        focus_storage.wrappedValue = newValue
                    }
                }

                private let focus_storage: FocusState<Field?> = FocusState()

                private let log_focus = TestLog()

                private var `$focus`: FocusState<Field?>.Binding {
                    focus_storage.projectedValue
                }
            }
            """,
            macros: macros
        )
    }
}
