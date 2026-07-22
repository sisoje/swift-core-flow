import Testing
import CoreFlow

// `assertMacroExpansion` (see PickMacroTests) only checks syntactic
// expansion — it never resolves whether the emitted code actually
// typechecks, and it doesn't exercise Swift's real overload resolution
// across #pick's one/two/three-source overloads either. This suite is the
// executable counterpart: real `#pick` calls, actually compiled by the
// host toolchain, exercised at runtime.

private typealias Store = (expenses: [Int], limit: Int, name: String)
private typealias Actions = (alerts: [String], submit: () -> Void)

@Suite struct EndToEndTests {

    @Test func pickProjectsMultipleFields() {
        let store: Store = (expenses: [1, 2, 3], limit: 10, name: "Groceries")
        let picked = #pick(from: store, \.expenses, \.limit)
        #expect(picked.0 == [1, 2, 3])
        #expect(picked.1 == 10)
    }

    @Test func pickSingleFieldReturnsBareValue() {
        // #pick's DECLARED signature returns `(repeat each V)` — parameter
        // packs can't carry per-element labels in today's Swift, so despite
        // the expansion body building a labeled tuple literal, the call
        // site's static type is positional. Access by index, not by label.
        let store: Store = (expenses: [], limit: 7, name: "Rent")
        let picked = #pick(from: store, \.limit)
        #expect(picked == 7)
    }

    @Test func pickRenameOverridesTheDerivedLabelAndReorders() {
        // The rename only affects the label visible via "Expand Macro"/at
        // the source level, not a named accessor on the result (see the
        // note on pickSingleFieldReturnsBareValue above). What's under test
        // here is that the VALUES land in written order: total (renamed
        // from .limit) first, then expenses.
        let store: Store = (expenses: [1, 2], limit: 9, name: "Rent")
        let picked = #pick(from: store, \.limit => "total", \.expenses)
        #expect(picked.0 == 9)
        #expect(picked.1 == [1, 2])
    }

    @Test func pickWorksDirectlyOnABareTupleValueNoBridgingNeeded() {
        // Verified separately (see README) that this toolchain actually
        // implements tuple KeyPaths — so #pick needs no bridging through a
        // struct mirror to work on a raw tuple with heterogeneous field
        // types. `store` here is a plain tuple typealias, not a struct.
        let store: Store = (expenses: [1, 2, 3], limit: 4, name: "Utilities")
        let picked = #pick(from: store, \.name, \.expenses, \.limit)
        #expect(picked.0 == "Utilities")
        #expect(picked.1 == [1, 2, 3])
        #expect(picked.2 == 4)
    }

    @Test func pickOfPickComposesOnATupleValue() {
        let store: Store = (expenses: [7, 8], limit: 3, name: "Rent")
        let inner = #pick(from: store, \.expenses, \.limit)
        let outer = #pick(from: inner, \.0)
        #expect(outer == [7, 8])
    }

    @Test func groupedPickCombinesTwoSources() {
        let store: Store = (expenses: [12, 40, 7], limit: 100, name: "Groceries")
        let actions: Actions = (alerts: ["low battery"], submit: {})
        let merged = #pick(from: store, \.expenses, \.limit, from: actions, \.alerts)
        #expect(merged.0 == [12, 40, 7])
        #expect(merged.1 == 100)
        #expect(merged.2 == ["low battery"])
    }

    @Test func groupedPickBindsARepeatedSourceOnceAcrossGroups() {
        let store: Store = (expenses: [1, 2], limit: 5, name: "Rent")
        let actions: Actions = (alerts: ["low"], submit: {})
        let merged = #pick(
            from: store, \.expenses, \.limit, from: actions, \.alerts, from: store, \.name)
        #expect(merged.0 == [1, 2])
        #expect(merged.1 == 5)
        #expect(merged.2 == ["low"])
        #expect(merged.3 == "Rent")
    }

    @Test func groupedPickThreeSourcesCompilesAgainstTheFullyTypedOverload() {
        let store: Store = (expenses: [1], limit: 2, name: "Rent")
        let actions: Actions = (alerts: ["a"], submit: {})
        let merged = #pick(
            from: store, \.expenses, from: actions, \.alerts, from: store, \.limit => "total")
        #expect(merged.0 == [1])
        #expect(merged.1 == ["a"])
        #expect(merged.2 == 2)
    }
}
