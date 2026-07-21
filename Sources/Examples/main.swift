import Foundation
import SwiftData
import SwiftUI
import ValueFlow

@Model public final class Item {
    var int = 0
    init() {}
}

// MARK: - Flowable

// @Flowable writes the memberwise initializer at the struct's own access
// level — the `public init` Swift refuses to synthesize for a public type — plus an
// `InFlowSplat` typealias bundling the same properties into an UNLABELED tuple
// alongside it:
// `public typealias InFlowSplat = (UUID, String, Bool, @MainActor () -> Void,
//     () async -> Void, @Sendable (String, Int) async -> Void, (() -> Void)?)`
// — no defaults, no @escaping, unlike the init right above it (tuple element types
// support neither). Also generates `makeFlow(_:)`, building Self back from
// an InFlowSplat value:
// `static func makeFlow(_ flow: InFlowSplat) -> Self { Self(x: flow.0, y: flow.1) }`.
// Unlabeled specifically so ANY structurally-compatible tuple converts in, not just
// one built with these exact field names/order in mind:

@Flowable
public struct Point {
    var x: Int
    var y: Int
}

@Flowable
public struct OneValur {
    var x: Int
}

// A differently-labeled tuple value swallows/"splats" right in — verified this
// fails against a *labeled* InFlow (real type error, not a macro bug) but
// succeeds once InFlowSplat is unlabeled: Swift only enforces label agreement
// between two labeled tuple types, not into an unlabeled one.
let keke = (xxx: 1, yyy: 1)

let p = Point.makeFlow(keke)

@Flowable
public struct User {
    static let x: Int = 0
    static var y: Int {
        0
    }

    var x: Int {
        0
    }

    public let id: UUID
    public let name: String
    var isActive: Bool = false  // inline default → defaulted parameter
    public let onmain: @MainActor () -> Void
    public let onChange: () async -> Void  // function type → @escaping param
    public let onRename: @Sendable (String, Int) async -> Void  // attributed function type → @escaping param
    public var onDone: (() -> Void)?  // optional var → `= nil` param, no @escaping
}

@Flowable
@Observable public final class Settings {
    var count: Int = 0  // one property → `typealias InFlowSplat = Int`, no 1-tuple
}

// On a View: @State/@Environment are private, so they're excluded; @Binding is
// threaded as Binding<Bool>; @ViewBuilder carries onto the parameters. Generated init:
// `init(isOn: Binding<Bool>, title: String, subtitle: String? = nil, model: Settings,
//       @ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: () -> Content)`.
// The InFlowSplat typealias diverges from that init in two ways: no default for
// subtitle, and footer keeps its own type (`Content`) instead of the `() -> Content`
// builder the init uses — `typealias InFlowSplat = (Binding<Bool>, String, String?,
// Settings, () -> Content, Content)`, unlabeled like every InFlowSplat.
// makeFlow(_:) re-wraps footer into a closure to satisfy the init's builder
// param, reading positionally: `Self(isOn: flow.0, ..., footer: { flow.5 })`.
// @Shell auto-detects View/ViewModifier off the attached type's own
// inheritance clause (syntactically — see ShellMacro.swift's
// `detectHostKind`) and, when it matches, generates two more things beyond the
// usual Core struct/core property: `Core` itself is additionally
// declared `: View` (here) or `: ViewModifier` (VM, below), and ProfileCard gets
// a generated `var body: some View { core }` for free — the mechanical
// delegation, not hand-written. Only the *real* body implementation, on
// `Core` itself, is left for hand-written code below.
@Flowable
@Shell
public struct ProfileCard<Content: View>: View {
    // Namespace.wrappedValue has no setter and no projectedValue at all (verified
    // directly) — this macro can't thread it through an init parameter, so unlike
    // real-world SwiftUI (where non-private @Namespace is common), it's required
    // private here, same as @Environment. No explicit type needed, unlike every
    // other recognized wrapper: @Namespace has exactly one possible wrapped
    // type, Namespace.ID, so this macro fills it in without a type checker.
    @Namespace private var ns
    @FocusState private var focused: Bool  // @FocusState has no init(wrappedValue:) — no inline default allowed
    @Query(animation: Animation.bouncy) private var items: [Item]
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var counter = 0
    // @SceneStorage's wrappedValue is get/nonmutating-set and its projectedValue
    // genuinely IS Binding<Bool> (verified directly, same shape as @AppStorage) —
    // so it shares @State/@AppStorage's exact treatment: Binding<Bool> in OutFlow,
    // @Binding var in Core, both read via $isPinned.
    @SceneStorage("isPinned") private var isPinned = true
    @Binding var isOn: Bool
    var title = "a"
    var subtitle: String? = "x"
    @Bindable var model: Settings
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: Content
}

// The real implementation — Core already conforms to View (declared by the
// macro above), so this extension only needs to satisfy the requirement, not
// redeclare the conformance.
extension ProfileCard.Core {
    // colorScheme is a plain, internal `let` on Core — captured once when
    // `.core` was computed, same as every other field. Core itself
    // is always internal, regardless of ProfileCard's own `public` access — this
    // is a testing/internal-body seam, not part of ProfileCard's public API.
    var body: some View {
        Text(colorScheme == .dark ? title.uppercased() : title)
    }
}

// Same story for ViewModifier: @Shell sees `: ViewModifier` on VM and
// generates `func body(content: Content) -> some View { content.modifier(core) }`
// on VM, plus `: ViewModifier` on VM.Core — via `.modifier(_:)`, so there's
// no need to unify VM's own `Content` with VM.Core's (verified directly
// that forwarding `content` straight into Core's own `body(content:)`
// instead does not compile — see ShellMacro.swift's doc comment).
@Flowable
@Shell
public struct VM: ViewModifier {
    @State private var c: Int = 0
}

extension VM.Core {
    func body(content: Content) -> some View {
        content.opacity(c == 0 ? 1 : 0.5)
    }
}

// MARK: - TuplePicker

let store = (expenses: [12, 40, 7], limit: 100, name: "Groceries")
let actions = (alerts: ["low battery"], submit: {})

// #pick — multiple sources into one tuple
let merged = #pick(from: store, \.expenses => "zzz", \.limit, from: actions, \.alerts)

// #pick — picking 2 out of 11 fields from one large tuple
let big = (
    val1: 1, val2: 2, val3: 3, val4: 4, val5: 5, val6: 6, val7: 7, val8: 8, val9: 9, val10: 10,
    val11: 11
)
let twoOfEleven = #pick(from: big, \.val3, \.val11)

// MARK: - Capability

// @Capability bundles every eligible computed property/method into one
// `Capability` tuple typealias + `capability` computed property. Unlike
// @Flowable, it works fine on an extension — it collects
// COMPUTED members (which extensions can declare), not stored ones (which they
// can't). `me`, `zola`, `zola2` (stored) don't participate; `x` (computed),
// `doSomething`, `doSomethingElse`, `meme` (methods) do. Generated:
// `typealias Capability = (x: Int, doSomething: () -> Void, doSomethingElse: () -> Void, meme: () async throws -> Void)`
// `var capability: Capability { (x, doSomething, doSomethingElse, meme) }`
// No @Sendable on the fields — marking them unconditionally would fail to
// compile for any type capturing something non-Sendable; Swift 6's region-based
// checking already permits crossing actor/Task boundaries without it when the
// captured content actually is safe.
struct MySomething {
    private var me = 0
    let zola: Int
    var zola2: Int = 0
}

@Capability
extension MySomething {
    var x: Int {
        zola * me
    }

    func doSomething() {
        print(zola)
    }

    func doSomethingElse() {
        print(zola2)
    }

    func meme() async throws {
        try await Task.sleep(nanoseconds: 1)
    }
}

// MARK: - Reflector

// Reflector.fieldNames needs only a TYPE — no instance — so it names
// Point.InFlow's fields directly off Point.self, without ever constructing a
// Point: the same names Point's `inFlow` property returns values for.
let pointFieldNames = Reflector.fieldNames(of: Point.InFlow.self)  // ["x", "y"]

// Works equally on a struct containing a class-typed field — the crash
// Reflector's precondition guards against is about T's own top-level kind
// being a class, not about what its fields are.
let profileCardFieldNames = Reflector.fieldNames(of: ProfileCard<Text>.InFlow.self)

// Point OutFlow, not InFlow, to see isExpanded/isPinned/colorScheme/ns too —
// @State/@SceneStorage/@Environment/@Namespace are private, so InFlow excludes
// them entirely, but OutFlow includes every recognized private source-of-truth
// wrapper alongside the public data, no exceptions.
let profileCardOutFlowFieldNames = Reflector.fieldNames(of: ProfileCard<Text>.OutFlow.self)

// MARK: - OutFlow

// outFlow mixes InFlow's fields with the view's own externally-relevant
// CAPTURABLE private state — every recognized source-of-truth wrapper this
// package supports, no exceptions — in declaration order — not data-layout
// fields first, wrapper fields appended after: `ns` (@Namespace) comes first
// here because it's declared first on ProfileCard. @Query is always
// synthesized as (wrappedValue: WrappedType, fetchError: Error?), via #pick
// (this package's own TuplePicker macro, reused here rather than hand-rolled)
// — items: [Item] becomes items: (wrappedValue: [Item], fetchError: Error?).
// wrappedValue/fetchError are real members of SwiftData's Query wrapper
// instance, picked verbatim (#pick(from: _items, \.wrappedValue,
// \.fetchError)), not synthesized placeholders — modelContext is deliberately
// left out, plumbing for further queries/saves rather than a snapshot value
// worth asserting on. @State/@AppStorage/@SceneStorage all read as Binding<T>
// via the projected $ value — @SceneStorage's own projectedValue genuinely IS
// Binding<T>, verified directly, same shape as @State/@AppStorage exactly.
// @FocusState reads via that same `$x` shortcut, but resolves to its OWN
// projected type, FocusState<Bool>.Binding — not Binding<Bool> — since
// @FocusState's projectedValue has no public conversion to Binding<T>
// (verified directly). @Binding fields (isOn, below) read via that identical
// `$x` shortcut too — verified directly that $isOn and the backing-storage
// _isOn give the same Binding<Bool>; _isOn is kept only for the *assignment*
// side inside the generated init, where $isOn is immutable. @Environment/
// @Namespace read as plain values (colorScheme, ns), the same way any
// non-private field does — no exclusion: a captured value going stale, or
// @Environment's own mocking story, are things worth knowing about the
// snapshot, not reasons to leave the field out of it.
var isOnStorage = true
let profileCard = ProfileCard(
    isOn: Binding(get: { isOnStorage }, set: { isOnStorage = $0 }),
    title: "Settings",
    model: Settings(),
    content: { Text("content") },
    footer: { Text("footer") }
)
let profileCardOutFlow = profileCard.outFlow

// focused: FocusState<Bool>.Binding — its own real projected type, still
// carrying wrappedValue get/nonmutating-set, so it reads/writes exactly like
// any other OutFlow binding field despite not being Binding<Bool>.
let profileCardOutFlowFocused = profileCardOutFlow.focused.wrappedValue

// isPinned: Binding<Bool> — @SceneStorage folds into the exact same OutFlow
// mapping @State/@AppStorage already get, no separate case needed.
let profileCardOutFlowIsPinned = profileCardOutFlow.isPinned.wrappedValue

// MARK: - Core

// @Shell is a separate macro from @Flowable — doesn't replace OutFlow,
// works alongside it. Same field set as OutFlow, PLUS @Environment (which
// OutFlow leaves out but Core captures anyway), as a real nominal
// `Core` struct instead of a tuple — always internal (struct, fields, and
// the `core` property itself), regardless of ProfileCard's own `public`
// access: this is a testing/internal-body seam, not a public API surface, and
// carries no @Flowable — Swift's own memberwise-init synthesis already handles
// every field kind here the same way @Flowable's hand-written logic would. The
// rule: every field mirrors its ORIGINAL declaration's attribute and type, but
// NEVER its mutability — Core is a deterministic snapshot, so a field is
// `var` only where Swift's own property-wrapper rule forces it (a genuine
// @propertyWrapper type requires `var` storage); everything else is `let`,
// regardless of what the original was declared as. @State/@AppStorage/
// @SceneStorage are the one substitution, not a mirror — declared @Binding
// instead, since their storage can't be redeclared as itself on a plain
// struct; a genuine @Binding field like isOn already mirrors into that same
// form on its own (and stays `var`, since @Binding is itself a genuine
// property wrapper). @Environment becomes a plain `let` — no attribute at
// all, since @Environment's wrappedValue has no public setter and the
// attribute can't be preserved, but a plain unattributed value has no such
// restriction (see ProfileCard.Core above).
// @State/@Environment/@Query/@AppStorage/@SceneStorage must all be private —
// enforced with a diagnostic if violated, not accommodated.
let profileCardCore = profileCard.core
let profileCardCoreTitle = profileCardCore.title
profileCardCore.isOn = false  // writes straight through to the caller's Binding

// isPinned reads as a bare Bool here too — @SceneStorage folds into the exact
// same @Binding var substitution @State/@AppStorage already get.
let profileCardCoreIsPinned = profileCardCore.isPinned

// subtitle is a plain `var` on ProfileCard, but Core is a deterministic
// snapshot — it's `let subtitle: String?` here (not mirrored as `var`), so a fresh
// snapshot read is the only way to see a different value, not an in-place mutation.
let profileCardCoreSubtitle = profileCardCore.subtitle

// @Bindable mirrors verbatim — model is declared on Core exactly as
// ProfileCard declares it. @ViewBuilder mirrors too, but only for content
// (a stored closure, () -> Content) — footer (a stored value, Content) drops
// the attribute entirely instead: mirroring it there would make Swift's own
// synthesized init wrap the parameter in a builder closure just to satisfy
// it, for a value that's already built and just being copied through. So
// footer stays a plain `let footer: Content`, passed straight through with
// no wrapping needed on either side.
let profileCardCoreModel = profileCardCore.model
let profileCardCoreFooter = profileCardCore.footer

// focused reads as a bare Bool here — @FocusState<Bool>.Binding var focused: Bool
// is Core's own substituted attribute (distinct from @Binding, since
// @FocusState's projectedValue isn't Binding<T> — see the OutFlow section above),
// but it's the real wrapper, redeclared, not a fabricated stand-in: $focused
// hands back a genuine FocusState<Bool>.Binding usable directly with `.focused(_:)`.
let profileCardCoreFocused = profileCardCore.focused
_ = Text("search").focused(profileCardCore.$focused)
