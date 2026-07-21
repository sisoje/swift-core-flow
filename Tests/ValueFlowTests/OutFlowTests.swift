import SwiftUI
import Testing
import ValueFlow

// Real, compiled usage — same reasoning as EndToEndTests/ReflectorTests: exercise
// actual runtime behavior, not just the syntactic shape assertMacroExpansion
// checks (see DataLayoutTests for that side).

@DataLayout
struct Card: View {
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @Namespace private var ns
    @State private var isExpanded: Bool = false
    @SceneStorage("isPinned") private var isPinned: Bool = false
    @FocusState private var isFocused: Bool
    @Binding var isOn: Bool
    let title: String

    var body: some View { Text(title) }
}

// @MainActor is required, not stylistic — verified directly. Card conforms to
// View, which implicitly infers @MainActor isolation for the whole type; touching
// its members (including `outFlow`) from a nonisolated test function crosses that
// isolation boundary at runtime and traps (SIGTRAP) under Swift 6 strict
// concurrency, even though it merely reads a stored/computed property.
@MainActor
@Suite struct OutFlowTests {

    @Test func outFlowReadsDataLayoutFieldsAndRecognizedPrivateWrappersTogether() {
        var isOnStorage = true
        let isOnBinding = Binding<Bool>(get: { isOnStorage }, set: { isOnStorage = $0 })
        let card = Card(isOn: isOnBinding, title: "Settings")

        let out = card.outFlow
        // Every private source-of-truth wrapper this package recognizes
        // belongs in OutFlow, no exceptions — including @Environment and
        // @Namespace, captured as plain values the same way any non-private
        // field is (a captured snapshot going stale, or @Environment's own
        // mocking story, are reasons to know that going in, not reasons to
        // leave the field out of the snapshot entirely).
        #expect(out.isOn.wrappedValue == true)
        #expect(out.isExpanded.wrappedValue == false)
        #expect(out.isPinned.wrappedValue == false)
        #expect(out.isFocused.wrappedValue == false)
        #expect(out.title == "Settings")
        #expect(out.colorScheme == .light)  // default EnvironmentValues, no live view installed
        _ = out.ns  // just needs to be reachable — see ShellTests.swift for its own instability note
    }

    @Test func outFlowsBindingForARealBindingFieldWritesThrough() {
        // Unlike @State (see the test below), a genuine caller-supplied @Binding
        // really does write through, regardless of SwiftUI's view lifecycle — it's
        // just a getter/setter pair, not tied to view identity.
        var isOnStorage = false
        let isOnBinding = Binding<Bool>(get: { isOnStorage }, set: { isOnStorage = $0 })
        let card = Card(isOn: isOnBinding, title: "x")

        card.outFlow.isOn.wrappedValue = true
        #expect(isOnStorage == true)
    }

    @Test func outFlowsBindingForAStateFieldDoesNotWriteThroughOutsideALiveView() {
        // Verified directly: @State's storage only installs once SwiftUI actually
        // renders the view. A struct constructed directly in plain code — never
        // installed into a view hierarchy — has a `$state`-derived Binding that
        // silently no-ops on write instead of persisting. Not a bug in OutFlow;
        // it's how @State itself behaves outside SwiftUI's render pipeline. Anyone
        // reading OutFlow's isExpanded as a "real" mutable Binding outside a live
        // view needs to know this going in.
        let isOnBinding = Binding<Bool>(get: { true }, set: { _ in })
        let card = Card(isOn: isOnBinding, title: "x")

        card.outFlow.isExpanded.wrappedValue = true
        #expect(card.outFlow.isExpanded.wrappedValue == false)
    }

    @Test func outFlowsSceneStorageBindingDoesNotWriteThroughOutsideALiveView() {
        // Same caveat as @State's — verified directly for @SceneStorage too,
        // even though it's backed by persistent storage rather than in-memory
        // view identity: a write outside a live view silently no-ops instead
        // of persisting.
        let isOnBinding = Binding<Bool>(get: { true }, set: { _ in })
        let card = Card(isOn: isOnBinding, title: "x")

        card.outFlow.isPinned.wrappedValue = true
        #expect(card.outFlow.isPinned.wrappedValue == false)
    }

    @Test func outFlowsFocusStateBindingDoesNotWriteThroughOutsideALiveView() {
        // Same caveat as @State's — verified directly for @FocusState too: its
        // storage only installs once SwiftUI actually renders the view, so a
        // write to its own FocusState<Bool>.Binding here silently no-ops
        // instead of persisting.
        let isOnBinding = Binding<Bool>(get: { true }, set: { _ in })
        let card = Card(isOn: isOnBinding, title: "x")

        card.outFlow.isFocused.wrappedValue = true
        #expect(card.outFlow.isFocused.wrappedValue == false)
    }
}
