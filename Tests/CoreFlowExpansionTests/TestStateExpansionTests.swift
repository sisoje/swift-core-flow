@testable import CoreFlowMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class TestStateExpansionTests: XCTestCase {
    let macros: [String: Macro.Type] = [
        "TestState": TestStateMacro.self,
        "TestAction": TestActionMacro.self,
        "TestFocusState": TestFocusStateMacro.self,
    ]

    func testStateExpansion() {
        assertMacroExpansion(
            """
            struct Host {
                @TestState private var count: Int = 0
            }
            """,
            expandedSource: """
            struct Host {
                private var count: Int {
                    @storageRestrictions(initializes: count_storage)
                    init(initialValue) {
                        count_storage = State(wrappedValue: initialValue)
                    }
                    get {
                        count_storage.wrappedValue
                    }
                    nonmutating set {
                        log_count.wrappedValue("count", String(describing: newValue))
                        count_storage.wrappedValue = newValue
                    }
                }

                private let count_storage: State<Int>

                private let log_count = TestLog()

                private var `$count`: Binding<Int> {
                    Binding(
                        get: {
                            self.count
                        },
                        set: {
                            self.count = $0
                        }
                    )
                }
            }
            """,
            macros: macros
        )
    }

    // A bare literal default infers its type; a var closure is state like any
    // other — its binding mutates the closure itself, deliberately no exception.

    func testStateLiteralInferenceAndVarClosure() {
        assertMacroExpansion(
            """
            struct Host {
                @TestState private var isOn = false
                @TestState private var jump: () -> Void = {}
            }
            """,
            expandedSource: """
            struct Host {
                private var isOn {
                    @storageRestrictions(initializes: isOn_storage)
                    init(initialValue) {
                        isOn_storage = State(wrappedValue: initialValue)
                    }
                    get {
                        isOn_storage.wrappedValue
                    }
                    nonmutating set {
                        log_isOn.wrappedValue("isOn", String(describing: newValue))
                        isOn_storage.wrappedValue = newValue
                    }
                }

                private let isOn_storage: State<Bool>

                private let log_isOn = TestLog()

                private var `$isOn`: Binding<Bool> {
                    Binding(
                        get: {
                            self.isOn
                        },
                        set: {
                            self.isOn = $0
                        }
                    )
                }
                private var jump: () -> Void {
                    @storageRestrictions(initializes: jump_storage)
                    init(initialValue) {
                        jump_storage = State(wrappedValue: initialValue)
                    }
                    get {
                        jump_storage.wrappedValue
                    }
                    nonmutating set {
                        log_jump.wrappedValue("jump", String(describing: newValue))
                        jump_storage.wrappedValue = newValue
                    }
                }

                private let jump_storage: State<() -> Void>

                private let log_jump = TestLog()

                private var `$jump`: Binding<() -> Void> {
                    Binding(
                        get: {
                            self.jump
                        },
                        set: {
                            self.jump = $0
                        }
                    )
                }
            }
            """,
            macros: macros
        )
    }
}
