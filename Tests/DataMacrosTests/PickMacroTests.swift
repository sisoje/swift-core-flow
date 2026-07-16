import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import DataMacrosMacros

private let testMacros: [String: Macro.Type] = [
    "pick": PickMacro.self,
]

@Suite struct PickMacroTests {

    @Test func singlePickReturnsBareValue() {
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

    @Test func multiPickReturnsLabeledTuple() {
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

    @Test func chainedPickUsesLastComponentAsLabel() {
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

    @Test func renameOverridesTheDerivedLabel() {
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

    @Test func renameComposesWithReorderingOutputFollowsWrittenOrder() {
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

    @Test func twoSourcePickFollowsWrittenOrder() {
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

    @Test func repeatedValueAcrossSourcesIsBoundOnceNotTwice() {
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

    @Test func renameWorksAcrossSources() {
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

    @Test func duplicateLabelProducesDiagnosticWithRenameFixIt() {
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
                )
            ],
            macros: testMacros
        )
    }

    @Test func duplicateLabelAcrossSourcesProducesDiagnosticWithFixIt() {
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
                )
            ],
            macros: testMacros
        )
    }

    @Test func renameCollidingWithAnotherFieldsDerivedLabelProducesDiagnostic() {
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
                )
            ],
            macros: testMacros
        )
    }

    @Test func sourceWithNoPicksProducesDiagnostic() {
        assertMacroExpansion(
            "#pick(from: store, from: actions, \\.alerts)",
            expandedSource: "#pick(from: store, from: actions, \\.alerts)",
            diagnostics: [
                DiagnosticSpec(
                    message: "#pick: group 'from: store' has no picks",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    @Test func nonKeyPathTokenProducesDiagnosticNamingTheToken() {
        assertMacroExpansion(
            "#pick(from: store, limit)",
            expandedSource: "#pick(from: store, limit)",
            diagnostics: [
                DiagnosticSpec(
                    message: "#pick group 'from: store': expected a key path like \\.field "
                        + "(optionally `=> \"rename\"`), got 'limit'",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    @Test func nonStringRenameLiteralProducesDiagnostic() {
        assertMacroExpansion(
            "#pick(from: store, \\.limit => total)",
            expandedSource: "#pick(from: store, \\.limit => total)",
            diagnostics: [
                DiagnosticSpec(
                    message: "#pick group 'from: store': the rename after '=>' must be a plain "
                        + "string literal, got 'total'",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    @Test func missingFromLabelProducesDiagnostic() {
        assertMacroExpansion(
            "#pick(store, \\.limit)",
            expandedSource: "#pick(store, \\.limit)",
            diagnostics: [
                DiagnosticSpec(
                    message: "#pick: every source starts with 'from:', e.g. "
                        + "#pick(from: store, \\.a, \\.b) or #pick(from: store, \\.a, from: actions, \\.b)",
                    line: 1,
                    column: 1
                )
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

    @Test func tupleSourceWithHeterogeneousFieldTypesExpandsLikeAnyOtherSource() {
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

    // NOTE on composition: `#pick(from: #pick(from: t, \.a, \.b), \.a)` —
    // literally nesting one #pick call inside another's arguments, as ONE
    // expression — does NOT compile, for ANY combination of arities. Every
    // arity of #pick shares the same implementation type (PickMacro), and
    // Swift refuses to expand the same macro implementation type from
    // within its own expansion tree, even though the two invocations here
    // have entirely distinct arguments; there's no syntactic distinction it
    // makes between "textually nested" and "actually recursive." The
    // working form splits into two statements —
    // `let inner = #pick(from: t, \.a, \.b); let outer = #pick(from: inner, \.a)`
    // — which is what EndToEndTests.pickOfPickComposesOnATupleValue
    // exercises for real. See the README for the full error.
}
