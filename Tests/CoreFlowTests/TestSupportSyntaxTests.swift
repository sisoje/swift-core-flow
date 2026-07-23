import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import CoreFlowMacros

final class TestSupportSyntaxTests: XCTestCase {
    let macros: [String: Macro.Type] = [
        "TestState": TestStateMacro.self,
        "TestAction": TestActionMacro.self,
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

                    private let log_count = Environment(\\.testLog)

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

                    private let log_isOn = Environment(\\.testLog)

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

                    private let log_jump = Environment(\\.testLog)

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

    func testActionArityAndEffects() {
        assertMacroExpansion(
            """
            struct Host {
                @TestAction private var refresh: () -> Void = {}
                @TestAction private var save: (String) -> Void = { _ in }
                @TestAction private var fetch: @Sendable (Int, Bool) async throws -> [String] = { _, _ in [] }
                @TestAction private var ping: (Int) async -> Void = { _ in }
            }
            """,
            expandedSource: """
                struct Host {
                    private var refresh: () -> Void {
                        @storageRestrictions(initializes: refresh_storage)
                        init(initialValue) {
                            refresh_storage = initialValue
                        }
                        get {
                            let log = log_refresh.wrappedValue
                            let storage = refresh_storage
                            return {
                                log("refresh", "")
                                storage()
                            }
                        }
                    }

                    private let refresh_storage: () -> Void

                    private let log_refresh = Environment(\\.testLog)
                    private var save: (String) -> Void {
                        @storageRestrictions(initializes: save_storage)
                        init(initialValue) {
                            save_storage = initialValue
                        }
                        get {
                            let log = log_save.wrappedValue
                            let storage = save_storage
                            return { a0 in
                                log("save", String(describing: a0))
                                storage(a0)
                            }
                        }
                    }

                    private let save_storage: (String) -> Void

                    private let log_save = Environment(\\.testLog)
                    private var fetch: @Sendable (Int, Bool) async throws -> [String] {
                        @storageRestrictions(initializes: fetch_storage)
                        init(initialValue) {
                            fetch_storage = initialValue
                        }
                        get {
                            let log = log_fetch.wrappedValue
                            let storage = fetch_storage
                            return { a0, a1 in
                                await log("fetch", String(describing: (a0, a1)))
                                return try await storage(a0, a1)
                            }
                        }
                    }

                    private let fetch_storage: @Sendable (Int, Bool) async throws -> [String]

                    private let log_fetch = Environment(\\.testLog)
                    private var ping: (Int) async -> Void {
                        @storageRestrictions(initializes: ping_storage)
                        init(initialValue) {
                            ping_storage = initialValue
                        }
                        get {
                            let log = log_ping.wrappedValue
                            let storage = ping_storage
                            return { a0 in
                                log("ping", String(describing: a0))
                                await storage(a0)
                            }
                        }
                    }

                    private let ping_storage: (Int) async -> Void

                    private let log_ping = Environment(\\.testLog)
                }
                """,
            macros: macros
        )
    }

    // Shapes each macro can't spell generate nothing — the use site expecting
    // the missing $name fails in the compiler's own words instead.
    func testUnspellableShapesAreSkipped() {
        assertMacroExpansion(
            """
            struct Host {
                @TestState private let title: String = "t"
                @TestState private var seed: CGFloat
                @TestAction private let limit: Int = 1
                @TestAction private var bare: () -> Void
            }
            """,
            expandedSource: """
                struct Host {
                    private let title: String = "t"
                    private var seed: CGFloat
                    private let limit: Int = 1
                    private var bare: () -> Void
                }
                """,
            macros: macros
        )
    }
}
