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

    @Test func coreModelCapturesEveryWriteThroughItsBindings() {
        // The generated CoreModel — @Observable @MainActor final class, one
        // `var` per Binding-typed Core field (the @State/@SceneStorage
        // substitutes plus the genuine @Binding), init params carrying the
        // host's defaults (so only defaultless `isOn` is required). Proves
        // two things at once: the @Observable macro expands correctly inside
        // @Shell's own generated code, and Bindable(model).x hands back a
        // real write-through Binding in plain code — every write the copied
        // body (or a test) makes through Core lands on the model.
        let model = StatefulCard.CoreModel(isOn: true)
        #expect(model.isExpanded == false)  // host default carried over
        let bindable = Bindable(model)
        let snap = StatefulCard.Core(
            isExpanded: bindable.isExpanded,
            isPinned: bindable.isPinned,
            isOn: bindable.isOn,
            title: "t",
            subtitle: nil
        )
        #expect(model.history.isEmpty)  // observers never fire during init
        snap.isExpanded = true
        snap.isOn = false
        snap.isPinned = true
        #expect(model.isExpanded == true)
        #expect(model.isOn == false)
        // Every property's didSet appends (propertyName:, value:) to
        // history — the model records the exact write sequence, order
        // included, and the tuple shape lets a test slice it: assert the
        // full sequence by name, or filter to one property and ignore the
        // rest entirely.
        #expect(model.history.map(\.propertyName) == ["isExpanded", "isOn", "isPinned"])
        let isOnWrites = model.history
            .filter { $0.propertyName == "isOn" }
            .compactMap { $0.value as? Bool }
        #expect(isOnWrites == [false])
    }

    @Test func makeWiresEveryBindingToTheModelInOneCall() {
        // Core.make — the one-call test constructor: every memberwise
        // parameter except the Binding-typed ones, plus the model those
        // bindings come from; inside, a local `@Bindable var model = model`
        // shadow supplies `$model.x` for each. Defaults ride along
        // (subtitle's implicit nil), so a full StatefulCard.Core mock is one
        // line — then the history records what happened, as usual.
        let model = StatefulCard.CoreModel(isOn: true)
        let snap = StatefulCard.Core.make(model: model, title: "t")
        #expect(snap.title == "t")
        #expect(snap.isOn == true)
        snap.isOn = false
        snap.isExpanded = true
        #expect(model.history.map(\.propertyName) == ["isOn", "isExpanded"])
        #expect(model.isOn == false)
        #expect(model.isExpanded == true)
    }

    @Test func coreFieldsStayMutableForReMocking() {
        // Every Core field is `var` — a copy can be re-mocked field by field.
        var mutable = makeCore()
        mutable.subtitle = "remocked"
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
