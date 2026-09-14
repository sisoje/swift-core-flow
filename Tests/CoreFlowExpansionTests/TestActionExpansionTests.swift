@testable import CoreFlowMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class TestActionExpansionTests: XCTestCase {
    let macros: [String: Macro.Type] = [
        "TestState": TestStateMacro.self,
        "TestAction": TestActionMacro.self,
        "TestFocusState": TestFocusStateMacro.self,
    ]

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

                private let log_refresh = TestLog()
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

                private let log_save = TestLog()
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

                private let log_fetch = TestLog()
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

                private let log_ping = TestLog()
            }
            """,
            macros: macros
        )
    }
}
