@testable import CoreFlowMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class FlowUpExpansionTests: XCTestCase {
    let macros: [String: Macro.Type] = [
        "FlowUp": FlowUpMacro.self,
    ]

    func testExpansion() {
        // The accessor is the consumer entry: a genuine closure over the
        // hidden storage, the forwarding loop's only home. Peers: the tag
        // (per-name identity), the hand-rolled environment entry (native
        // @Entry refuses to expand inside another macro's expansion), and
        // the same-named static _FlowUpID. Effects mirror the declared
        // type: try await.
        assertMacroExpansion(
            """
            extension EnvironmentValues {
                @FlowUp var handleUrl: (URL) async throws -> Void
            }
            """,
            expandedSource: """
            extension EnvironmentValues {
                var handleUrl: (URL) async throws -> Void {
                    get {
                        let wrappers = self.handleUrl_closures
                        return { a0 in
                            for wrapper in wrappers {
                                for closure in wrapper.closures {
                                    try await closure(a0)
                                }
                            }
                        }
                    }
                }

                enum handleUrl_Key: EnvironmentKey {
                    static var defaultValue: [_FlowUpClosure<(URL) async throws -> Void>] {
                        []
                    }
                }

                fileprivate var handleUrl_closures: [_FlowUpClosure<(URL) async throws -> Void>] {
                    get {
                        self[handleUrl_Key.self]
                    }
                    set {
                        self[handleUrl_Key.self] = newValue
                    }
                }

                static var handleUrl: _FlowUpID<handleUrl_Key, (URL) async throws -> Void> {
                    _FlowUpID(keyPath: \\.handleUrl_closures)
                }
            }
            """,
            macros: macros
        )
    }

    func testZeroArgumentSynchronousExpansion() {
        // No parameters, no closure signature; no effects, bare call.
        assertMacroExpansion(
            """
            extension EnvironmentValues {
                @FlowUp var refresh: () -> Void
            }
            """,
            expandedSource: """
            extension EnvironmentValues {
                var refresh: () -> Void {
                    get {
                        let wrappers = self.refresh_closures
                        return {
                            for wrapper in wrappers {
                                for closure in wrapper.closures {
                                    closure()
                                }
                            }
                        }
                    }
                }

                enum refresh_Key: EnvironmentKey {
                    static var defaultValue: [_FlowUpClosure<() -> Void>] {
                        []
                    }
                }

                fileprivate var refresh_closures: [_FlowUpClosure<() -> Void>] {
                    get {
                        self[refresh_Key.self]
                    }
                    set {
                        self[refresh_Key.self] = newValue
                    }
                }

                static var refresh: _FlowUpID<refresh_Key, () -> Void> {
                    _FlowUpID(keyPath: \\.refresh_closures)
                }
            }
            """,
            macros: macros
        )
    }

    func testPublicAnchorCopiesAccessOntoTagAndStatic() {
        // The static's return type names the tag, so a public static needs
        // a public tag; the storage stays fileprivate regardless.
        assertMacroExpansion(
            """
            extension EnvironmentValues {
                @FlowUp public var shared: (Int, String) -> Void
            }
            """,
            expandedSource: """
            extension EnvironmentValues {
                public var shared: (Int, String) -> Void {
                    get {
                        let wrappers = self.shared_closures
                        return { a0, a1 in
                            for wrapper in wrappers {
                                for closure in wrapper.closures {
                                    closure(a0, a1)
                                }
                            }
                        }
                    }
                }

                public enum shared_Key: EnvironmentKey {
                    public static var defaultValue: [_FlowUpClosure<(Int, String) -> Void>] {
                        []
                    }
                }

                fileprivate var shared_closures: [_FlowUpClosure<(Int, String) -> Void>] {
                    get {
                        self[shared_Key.self]
                    }
                    set {
                        self[shared_Key.self] = newValue
                    }
                }

                public static var shared: _FlowUpID<shared_Key, (Int, String) -> Void> {
                    _FlowUpID(keyPath: \\.shared_closures)
                }
            }
            """,
            macros: macros
        )
    }

    func testAttributedClosureTypeRidesVerbatim() {
        // @MainActor rides the full type text into every generic position.
        assertMacroExpansion(
            """
            extension EnvironmentValues {
                @FlowUp var ping: @MainActor (Int) -> Void
            }
            """,
            expandedSource: """
            extension EnvironmentValues {
                var ping: @MainActor (Int) -> Void {
                    get {
                        let wrappers = self.ping_closures
                        return { a0 in
                            for wrapper in wrappers {
                                for closure in wrapper.closures {
                                    closure(a0)
                                }
                            }
                        }
                    }
                }

                enum ping_Key: EnvironmentKey {
                    static var defaultValue: [_FlowUpClosure<@MainActor (Int) -> Void>] {
                        []
                    }
                }

                fileprivate var ping_closures: [_FlowUpClosure<@MainActor (Int) -> Void>] {
                    get {
                        self[ping_Key.self]
                    }
                    set {
                        self[ping_Key.self] = newValue
                    }
                }

                static var ping: _FlowUpID<ping_Key, @MainActor (Int) -> Void> {
                    _FlowUpID(keyPath: \\.ping_closures)
                }
            }
            """,
            macros: macros
        )
    }

    func testNonFunctionTypeIsRefused() {
        assertMacroExpansion(
            """
            extension EnvironmentValues {
                @FlowUp var handleUrl: Int
            }
            """,
            expandedSource: """
            extension EnvironmentValues {
                var handleUrl: Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                    "@FlowUp requires a stored instance 'var' with a function-type annotation and no initial value.",
                    line: 2,
                    column: 5
                ),
            ],
            macros: macros
        )
    }

    func testInlineDefaultIsRefused() {
        assertMacroExpansion(
            """
            extension EnvironmentValues {
                @FlowUp var handleUrl: (URL) -> Void = { _ in }
            }
            """,
            expandedSource: """
            extension EnvironmentValues {
                var handleUrl: (URL) -> Void = { _ in }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                    "@FlowUp requires a stored instance 'var' with a function-type annotation and no initial value.",
                    line: 2,
                    column: 5
                ),
            ],
            macros: macros
        )
    }

    func testLetIsRefused() {
        assertMacroExpansion(
            """
            extension EnvironmentValues {
                @FlowUp let handleUrl: (URL) -> Void
            }
            """,
            expandedSource: """
            extension EnvironmentValues {
                let handleUrl: (URL) -> Void
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                    "@FlowUp requires a stored instance 'var' with a function-type annotation and no initial value.",
                    line: 2,
                    column: 5
                ),
            ],
            macros: macros
        )
    }

    func testNonVoidReturnIsRefused() {
        assertMacroExpansion(
            """
            extension EnvironmentValues {
                @FlowUp var validate: (String) -> Bool
            }
            """,
            expandedSource: """
            extension EnvironmentValues {
                var validate: (String) -> Bool
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                    "@FlowUp requires a 'Void'-returning closure type: N listeners have no single combined result.",
                    line: 2,
                    column: 5
                ),
            ],
            macros: macros
        )
    }

    func testWrongExtensionIsRefused() {
        assertMacroExpansion(
            """
            extension Card {
                @FlowUp var handleUrl: (URL) -> Void
            }
            """,
            expandedSource: """
            extension Card {
                var handleUrl: (URL) -> Void
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                    "@FlowUp must be attached inside 'extension EnvironmentValues'.",
                    line: 2,
                    column: 5
                ),
            ],
            macros: macros
        )
    }
}
