import SwiftUI
import Testing
import ValueFlow

// Real, compiled usage — same reasoning as OutFlowTests: exercise actual runtime
// behavior, not just the syntactic shape assertMacroExpansion checks (see
// ShellSyntaxTests for that side). @Flowable and @Shell coexist on one
// type here specifically to verify they don't interfere with each other — even
// though Core itself never carries @Flowable (see ShellRendering.swift),
// relying instead on Swift's own memberwise-init synthesis.

@Flowable
@Shell
struct StatefulCard: View {
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @Namespace private var ns: Namespace.ID
    @State private var isExpanded: Bool = false
    @SceneStorage("isPinned") private var isPinned: Bool = false
    @FocusState private var isFocused: Bool
    @GestureState private var dragOffset: CGSize = .zero
    @Binding var isOn: Bool
    let title: String
    var subtitle: String?

    // Written once, as ordinary SwiftUI — @Shell copies it verbatim into
    // Core, where the same identifiers resolve against the substituted
    // fields. `heading` below rides along the same way (every non-stored
    // member is copied).
    var body: some View {
        Text(heading)
    }

    var heading: String {
        colorScheme == .dark ? title.uppercased() : title
    }
}

/// Builds a fully-mocked Core directly — no live view, no host instance, no
/// SwiftUI render pipeline. Every substituted wrapper is fabricated from
/// plain code: `Binding` from a getter/setter pair, `FocusState<T>.Binding`
/// from a fresh `FocusState` instance's own projection (it has no public
/// initializer of its own — verified directly — but `FocusState()` mints one
/// fine outside a live view), `Namespace.ID` from a fresh `Namespace`, and
/// `GestureStateCore` by seeding a `GestureState` with any mid-gesture value.
@MainActor
private func makeCore(
    colorScheme: ColorScheme = .light,
    isOn: Binding<Bool> = .constant(true),
    dragOffset: CGSize = .zero,
    title: String = "x",
    subtitle: String? = nil
) -> StatefulCard.Core {
    StatefulCard.Core(
        colorScheme: colorScheme,
        ns: Namespace().wrappedValue,
        isExpanded: .constant(false),
        isPinned: .constant(false),
        isFocused: FocusState<Bool>().projectedValue,
        dragOffset: GestureStateCore(GestureState(wrappedValue: dragOffset)),
        isOn: isOn,
        title: title,
        subtitle: subtitle
    )
}

@MainActor
@Suite struct ShellTests {

    @Test func coreConstructsDirectlyAndReadsBareValues() {
        let snap = makeCore(title: "Settings")
        #expect(snap.isOn == true)  // bare Bool — @Binding unwraps on read
        #expect(snap.isExpanded == false)  // bare Bool, @State's @Binding substitution
        #expect(snap.isPinned == false)  // same substitution for @SceneStorage
        #expect(snap.isFocused == false)  // via @FocusState<Bool>.Binding's own unwrap
        #expect(snap.title == "Settings")
        #expect(snap.subtitle == nil)  // plain `let` on Core, regardless of the original `var`
    }

    @Test func copiedBodyAndHelperEvaluateAgainstMockedFields() {
        // `body` and the `heading` helper it calls were both copied verbatim
        // off the host — the whole point of the design: the identical code
        // runs against mocked, plain fields with no live view anywhere.
        let snap = makeCore(colorScheme: .dark, title: "abc")
        #expect(snap.heading == "ABC")
        _ = snap.body
    }

    @Test func bindingFieldWritesThroughRealStorage() {
        // A Binding is just a getter/setter pair, not tied to view identity —
        // writes through Core reach the backing storage.
        var isOnStorage = false
        let snap = makeCore(isOn: Binding(get: { isOnStorage }, set: { isOnStorage = $0 }))
        snap.isOn = true
        #expect(isOnStorage == true)
    }

    @Test func focusStateBindingPlugsIntoFocusedModifier() {
        // snap.$isFocused is a genuine FocusState<Bool>.Binding — not a
        // fabricated stand-in — so it feeds `.focused(_:)` directly.
        let snap = makeCore()
        _ = Text("hi").focused(snap.$isFocused)
    }

    @Test func capturedCoreCopyIsFullyReMockable() {
        // Every Core field is `var`, and every wrapper field carries a raw_
        // accessor (@RawProperty, stamped by @Shell inside its own expansion)
        // over the private _name backing storage Swift refuses to expose — so
        // a mutable copy can swap the wrapper INSTANCE itself, not just the
        // wrapped value.
        var mutable = makeCore()
        #expect(mutable.isExpanded == false)
        mutable.raw_isExpanded = .constant(true)
        #expect(mutable.isExpanded == true)
        mutable.subtitle = "remocked"  // plain field — var now, plain reassignment
        #expect(mutable.subtitle == "remocked")
    }

    @Test func gestureStateIsMockableViaASeededInstance() {
        // Outside a live view a GestureState reads back its seed (verified
        // directly), so any mid-gesture value mocks by seeding one; $x hands
        // back the real GestureState<CGSize> that .updating(_:) takes.
        let snap = makeCore(dragOffset: CGSize(width: 50, height: 7))
        #expect(snap.dragOffset == CGSize(width: 50, height: 7))
        let projected: GestureState<CGSize> = snap.$dragOffset
        #expect(projected.wrappedValue == CGSize(width: 50, height: 7))
    }
}
