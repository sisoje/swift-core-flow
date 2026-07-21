import Foundation
import SwiftData
import SwiftUI
import ValueFlow

@Model public final class Item {
    var int = 0
    init() {}
}

// MARK: - DataLayout

// @DataLayout writes the memberwise initializer at the struct's own access
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

@DataLayout
public struct Point {
    var x: Int
    var y: Int
}

@DataLayout
public struct OneValur {
    var x: Int
}

// A differently-labeled tuple value swallows/"splats" right in — verified this
// fails against a *labeled* InFlow (real type error, not a macro bug) but
// succeeds once InFlowSplat is unlabeled: Swift only enforces label agreement
// between two labeled tuple types, not into an unlabeled one.
let keke = (xxx: 1, yyy: 1)

let p = Point.makeFlow(keke)

@DataLayout
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

@DataLayout
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
// @StatelessNode auto-detects View/ViewModifier off the attached type's own
// inheritance clause (syntactically — see StatelessNodeMacro.swift's
// `detectHostKind`) and, when it matches, generates two more things beyond the
// usual StatelessNode struct/statelessNode property: `StatelessNode` itself is additionally
// declared `: View` (here) or `: ViewModifier` (VM, below), and ProfileCard gets
// a generated `var body: some View { self.statelessNode }` for free — the mechanical
// delegation, not hand-written. Only the *real* body implementation, on
// `StatelessNode` itself, is left for hand-written code below.
@DataLayout
@StatelessNode
public struct ProfileCard<Content: View>: View {
    @Query(animation: Animation.bouncy) private var items: [Item]
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var isExpanded: Bool = false
    @Binding var isOn: Bool
    let title: String
    var subtitle: String? = "x"
    @Bindable var model: Settings
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: Content
}

// The real implementation — StatelessNode already conforms to View (declared by the
// macro above), so this extension only needs to satisfy the requirement, not
// redeclare the conformance.
extension ProfileCard.StatelessNode {
    // colorScheme is a plain, internal `let` on StatelessNode — captured once when
    // `.statelessNode` was computed, same as every other field. StatelessNode itself
    // is always internal, regardless of ProfileCard's own `public` access — this
    // is a testing/internal-body seam, not part of ProfileCard's public API.
    var body: some View {
        Text(colorScheme == .dark ? title.uppercased() : title)
    }
}

// Same story for ViewModifier: @StatelessNode sees `: ViewModifier` on VM and
// generates `func body(content: Content) -> some View { content.modifier(self.statelessNode) }`
// on VM, plus `: ViewModifier` on VM.StatelessNode — via `.modifier(_:)`, so there's
// no need to unify VM's own `Content` with VM.StatelessNode's (verified directly
// that forwarding `content` straight into StatelessNode's own `body(content:)`
// instead does not compile — see StatelessNodeMacro.swift's doc comment).
@DataLayout
@StatelessNode
public struct VM: ViewModifier {
    @State private var c: Int = 0
}

extension VM.StatelessNode {
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
// @DataLayout, it works fine on an extension — it collects
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

// Point OutFlow, not InFlow, to see isExpanded too — @State is private, so
// InFlow excludes it entirely, but OutFlow includes @Query/@State/@AppStorage
// alongside the public data. colorScheme is NOT here — @Environment is
// deliberately excluded from OutFlow (see below), even though `StatelessNode`
// (below) captures it fine.
let profileCardOutFlowFieldNames = Reflector.fieldNames(of: ProfileCard<Text>.OutFlow.self)

// MARK: - OutFlow

// outFlow mixes InFlow's fields with the view's own externally-relevant
// CAPTURABLE private state (@Query/@State/@AppStorage — NOT @Environment, see
// below), in declaration order — not data-layout fields first, wrapper fields
// appended after: `items` (@Query) comes first here because it's declared first
// on ProfileCard. @Query is always synthesized as (result: WrappedType,
// fetchError: Error?, modelContext: ModelContext) — items: [Item] becomes
// items: (result: [Item], fetchError: Error?, modelContext: ModelContext).
// fetchError/modelContext are real members of SwiftData's Query wrapper instance
// (self._items.fetchError/.modelContext), not synthesized placeholders.
// @State/@AppStorage read as Binding<T> via the projected $ value.
//
// @Environment is excluded: not because it's uncapturable (a plain value works
// fine — StatelessNode, below, captures it exactly that way), but because a
// captured snapshot goes stale the moment the real environment changes, and
// @Environment's own mocking story (inject a different value where the type
// is hosted) already covers testing it without this package's help.
var isOnStorage = true
let profileCard = ProfileCard(
    isOn: Binding(get: { isOnStorage }, set: { isOnStorage = $0 }),
    title: "Settings",
    model: Settings(),
    content: { Text("content") },
    footer: { Text("footer") }
)
let profileCardOutFlow = profileCard.outFlow

// MARK: - StatelessNode

// @StatelessNode is a separate macro from @DataLayout — doesn't replace OutFlow,
// works alongside it. Same field set as OutFlow, PLUS @Environment (which
// OutFlow leaves out but StatelessNode captures anyway), as a real nominal
// `StatelessNode` struct instead of a tuple — always internal (struct, fields, and
// the `statelessNode` property itself), regardless of ProfileCard's own `public`
// access: this is a testing/internal-body seam, not a public API surface, and
// carries no @DataLayout — Swift's own memberwise-init synthesis already handles
// every field kind here the same way @DataLayout's hand-written logic would. The
// rule: every field mirrors its ORIGINAL declaration's attribute and type, but
// NEVER its mutability — StatelessNode is a deterministic snapshot, so a field is
// `var` only where Swift's own property-wrapper rule forces it (a genuine
// @propertyWrapper type requires `var` storage); everything else is `let`,
// regardless of what the original was declared as. @State/@AppStorage is the one
// substitution, not a mirror — declared @Binding instead, since their storage
// can't be redeclared as itself on a plain struct; a genuine @Binding field like
// isOn already mirrors into that same form on its own (and stays `var`, since
// @Binding is itself a genuine property wrapper). @Environment becomes a plain
// `let` — no attribute at all, since @Environment's wrappedValue has no public
// setter and the attribute can't be preserved, but a plain unattributed value has
// no such restriction (see ProfileCard.StatelessNode above).
// @State/@Environment/@Query/@AppStorage must all be private — enforced with a
// diagnostic if violated, not accommodated.
let profileCardStatelessNode = profileCard.statelessNode
let profileCardStatelessNodeTitle = profileCardStatelessNode.title
profileCardStatelessNode.isOn = false  // writes straight through to the caller's Binding

// subtitle is a plain `var` on ProfileCard, but StatelessNode is a deterministic
// snapshot — it's `let subtitle: String?` here (not mirrored as `var`), so a fresh
// snapshot read is the only way to see a different value, not an in-place mutation.
let profileCardStatelessNodeSubtitle = profileCardStatelessNode.subtitle

// @ViewBuilder/@Bindable mirror verbatim too — content/footer/model are declared
// on StatelessNode exactly as ProfileCard declares them, so this compiles unchanged.
let profileCardStatelessNodeModel = profileCardStatelessNode.model
let profileCardStatelessNodeFooter = profileCardStatelessNode.footer
