@testable import CoreFlowMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

private let testMacros: [String: Macro.Type] = [
    "pick": PickMacro.self,
]

final class PickExpansionTests: XCTestCase {
    func testSinglePickReturnsBareValue() {
        assertMacroExpansion(
            "#pick(from: value, \\.limit)",
            expandedSource: """
            {
                let __v0 = value;
                return __v0.limit
            }()
            """,
            macros: testMacros
        )
    }

    func testMultiPickReturnsLabeledTuple() {
        assertMacroExpansion(
            "#pick(from: value, \\.name, \\.limit)",
            expandedSource: """
            {
                let __v0 = value;
                return (name: __v0.name, limit: __v0.limit)
            }()
            """,
            macros: testMacros
        )
    }

    func testChainedPickUsesLastComponentAsLabel() {
        assertMacroExpansion(
            "#pick(from: value, \\.store.limit)",
            expandedSource: """
            {
                let __v0 = value;
                return __v0.store.limit
            }()
            """,
            macros: testMacros
        )
    }

    // MARK: - Rename via `=>`

    func testRenameOverridesTheDerivedLabel() {
        assertMacroExpansion(
            "#pick(from: store, \\.expenses, \\.limit => \"total\")",
            expandedSource: """
            {
                let __v0 = store;
                return (expenses: __v0.expenses, total: __v0.limit)
            }()
            """,
            macros: testMacros
        )
    }

    func testRenameComposesWithReorderingOutputFollowsWrittenOrder() {
        // `total` (renamed from .limit) is written BEFORE `expenses` here —
        // the output tuple's field order follows that, not the tuple's
        // original declaration order.
        assertMacroExpansion(
            "#pick(from: store, \\.limit => \"total\", \\.expenses)",
            expandedSource: """
            {
                let __v0 = store;
                return (total: __v0.limit, expenses: __v0.expenses)
            }()
            """,
            macros: testMacros
        )
    }

    // MARK: - Multiple sources

    func testTwoSourcePickFollowsWrittenOrder() {
        assertMacroExpansion(
            "#pick(from: store, \\.expenses, \\.limit, from: actions, \\.alerts)",
            expandedSource: """
            {
                let __v0 = store;
                let __v1 = actions;
                return (expenses: __v0.expenses, limit: __v0.limit, alerts: __v1.alerts)
            }()
            """,
            macros: testMacros
        )
    }

    func testRepeatedValueAcrossSourcesIsBoundOnceNotTwice() {
        // `store` follows `from:` twice — one merged, interleaved result,
        // and only a single `let __v0 = store` (no `__v2`).
        assertMacroExpansion(
            "#pick(from: store, \\.expenses, \\.limit, from: actions, \\.alerts, from: store, \\.name)",
            expandedSource: """
            {
                let __v0 = store;
                let __v1 = actions;
                return (expenses: __v0.expenses, limit: __v0.limit, alerts: __v1.alerts, name: __v0.name)
            }()
            """,
            macros: testMacros
        )
    }

    func testRenameWorksAcrossSources() {
        assertMacroExpansion(
            "#pick(from: store, \\.limit => \"total\", from: actions, \\.alerts)",
            expandedSource: """
            {
                let __v0 = store;
                let __v1 = actions;
                return (total: __v0.limit, alerts: __v1.alerts)
            }()
            """,
            macros: testMacros
        )
    }

    // MARK: - Diagnostics

    func testDuplicateLabelProducesDiagnosticWithRenameFixIt() {
        assertMacroExpansion(
            "#pick(from: store, \\.limit, \\.limit)",
            expandedSource: """
            {
                fatalError("#pick: duplicate field labels")
            }()
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "#pick: duplicate field label 'limit' — rename this pick",
                    line: 1,
                    column: 29,
                    fixIts: [FixItSpec(message: "rename to \"limit2\"")]
                ),
            ],
            macros: testMacros
        )
    }

    func testDuplicateLabelAcrossSourcesProducesDiagnosticWithFixIt() {
        assertMacroExpansion(
            "#pick(from: store, \\.limit, from: actions, \\.limit)",
            expandedSource: """
            {
                fatalError("#pick: duplicate field labels")
            }()
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "#pick: duplicate field label 'limit' — rename this pick",
                    line: 1,
                    column: 44,
                    fixIts: [FixItSpec(message: "rename to \"limit2\"")]
                ),
            ],
            macros: testMacros
        )
    }

    func testRenameCollidingWithAnotherFieldsDerivedLabelProducesDiagnostic() {
        // \.limit is explicitly renamed to "total", which collides with the
        // plain \.total pick already deriving that same label.
        assertMacroExpansion(
            "#pick(from: store, \\.total, \\.limit => \"total\")",
            expandedSource: """
            {
                fatalError("#pick: duplicate field labels")
            }()
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "#pick: duplicate field label 'total' — rename this pick",
                    line: 1,
                    column: 29,
                    fixIts: [FixItSpec(message: "rename to \"total2\"")]
                ),
            ],
            macros: testMacros
        )
    }

    func testSourceWithNoPicksProducesDiagnostic() {
        assertMacroExpansion(
            "#pick(from: store, from: actions, \\.alerts)",
            expandedSource: "#pick(from: store, from: actions, \\.alerts)",
            diagnostics: [
                DiagnosticSpec(
                    message: "#pick: group 'from: store' has no picks",
                    line: 1,
                    column: 1
                ),
            ],
            macros: testMacros
        )
    }

    func testNonKeyPathTokenProducesDiagnosticNamingTheToken() {
        assertMacroExpansion(
            "#pick(from: store, limit)",
            expandedSource: "#pick(from: store, limit)",
            diagnostics: [
                DiagnosticSpec(
                    message: "#pick group 'from: store': expected a key path like \\.field "
                        + "(optionally `=> \"rename\"`), got 'limit'",
                    line: 1,
                    column: 1
                ),
            ],
            macros: testMacros
        )
    }

    func testNonStringRenameLiteralProducesDiagnostic() {
        assertMacroExpansion(
            "#pick(from: store, \\.limit => total)",
            expandedSource: "#pick(from: store, \\.limit => total)",
            diagnostics: [
                DiagnosticSpec(
                    message: "#pick group 'from: store': the rename after '=>' must be a plain "
                        + "string literal, got 'total'",
                    line: 1,
                    column: 1
                ),
            ],
            macros: testMacros
        )
    }

    func testMissingFromLabelProducesDiagnostic() {
        assertMacroExpansion(
            "#pick(store, \\.limit)",
            expandedSource: "#pick(store, \\.limit)",
            diagnostics: [
                DiagnosticSpec(
                    message: "#pick: every source starts with 'from:', e.g. "
                        + "#pick(from: store, \\.a, \\.b) or #pick(from: store, \\.a, from: actions, \\.b)",
                    line: 1,
                    column: 1
                ),
            ],
            macros: testMacros
        )
    }

    // MARK: - Bare tuple sources

    //
    // Checks the EXPANSION's syntax only (assertMacroExpansion never resolves
    // types) — the actual claim that this works on tuple *values*, not just
    // structs, is verified for real in EndToEndTests, which compiles and
    // runs it. Composition (#pick of a #pick) is ALSO only tested there, and
    // only as two separate statements — see the note below.

    func testTupleSourceWithHeterogeneousFieldTypesExpandsLikeAnyOtherSource() {
        assertMacroExpansion(
            "#pick(from: t, \\.id, \\.name, \\.active)",
            expandedSource: """
            {
                let __v0 = t;
                return (id: __v0.id, name: __v0.name, active: __v0.active)
            }()
            """,
            macros: testMacros
        )
    }

    // NOTE on composition: two #pick calls resolving to the SAME declared
    // overload can't nest as one expression ("recursive expansion" — the
    // guard keys on the resolved overload, not the shared implementation
    // type; different arities DO nest — see TuplePicker.swift). The
    // two-statement form is what EndToEndTests exercises for real.
}
