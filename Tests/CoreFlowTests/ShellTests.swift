import CoreFlow
import SwiftUI
import Testing

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
/// SwiftUI render pipeline. The mapped wrappers are fabricated from plain
/// code: `Binding` from a getter/setter pair or `.constant`. The unmapped
/// wrappers — `colorScheme` (@Environment), `ns` (@Namespace), `isFocused`
/// (@FocusState), `dragOffset` (@GestureState) — have no parameter here at
/// all: their declarations are copied onto Core verbatim, `private` kept, so
/// as self-initializing private fields they drop out of Core's memberwise
/// init and just behave (default `EnvironmentValues`, a fresh namespace,
/// unfocused, a gesture at `.zero` — see
/// `copiedBodyAndHelperEvaluateAgainstTheDefaultEnvironment`).
@MainActor
private func makeCore(
    isOn: Binding<Bool> = .constant(true),
    title: String = "x",
    subtitle: String? = nil
) -> StatefulCard.Core {
    StatefulCard.Core(
        isExpanded: .constant(false),
        isPinned: .constant(false),
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
        #expect(snap.title == "Settings")
        #expect(snap.subtitle == nil)  // plain `let` on Core, regardless of the original `var`
    }

    @Test func copiedBodyAndHelperEvaluateAgainstTheDefaultEnvironment() {
        // `body` and the `heading` helper it calls were both copied verbatim
        // off the host — the identical code runs with no live view anywhere.
        // `heading` reads Core's own verbatim-copied @Environment colorScheme,
        // which outside a live view is the default EnvironmentValues (.light —
        // same behavior OutFlowTests verifies for the host's own wrapper), so
        // the title comes back un-uppercased. Mocking an environment *value*
        // is the one thing direct construction can't do — that's the
        // wrapper's own design (get-only, no wrappedValue init); hosted in a
        // preview, `.environment(\.colorScheme, .dark)` is the native story.
        let snap = makeCore(title: "abc")
        #expect(snap.heading == "abc")
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

    @Test func privateVerbatimWrappersAreCompletelySealed() {
        // @Environment/@FocusState/@GestureState/@Namespace are unknown to
        // @Shell and private on the host — their declarations are copied onto
        // Core verbatim, `private` kept, so a directly constructed Core
        // neither takes them as init parameters nor exposes their values, and
        // they get no raw_ accessor either (that's for non-private wrapper
        // fields): sealed, they just behave. All that's observable from
        // outside is that construction works without them and the copied
        // members still evaluate against Core's own live copies.
        let snap = makeCore(title: "t")
        #expect(snap.title == "t")
        _ = snap.body
    }
}
