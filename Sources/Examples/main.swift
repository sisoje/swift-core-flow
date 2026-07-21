import Foundation
import SwiftData
import SwiftUI
import ValueFlow

@Model public final class Item {
    var int = 0
    init() {}
}

// MARK: - Flowable

@Flowable
public struct Point {
    var x: Int
    var y: Int
}

@Flowable
public struct OneValur {
    var x: Int
}

// InFlowSplat is unlabeled — any structurally-compatible tuple splats in.
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
    public let onRename: @Sendable (String, Int) async -> Void
    public var onDone: (() -> Void)?  // optional var → `= nil` param, no @escaping
}

@Flowable
@Observable public final class Settings {
    var count: Int = 0  // one property → `typealias InFlowSplat = Int`, no 1-tuple
}

// @Shell detects `: View` and generates `var body: some View { core }` on the
// host — only Core's real body is hand-written, below.
@Flowable
@Shell
public struct ProfileCard<Content: View>: View {
    @GestureState private var dragOffset: CGSize = .zero
    @AccessibilityFocusState private var a11yFocused: Bool
    @ScaledMetric private var iconSize: CGFloat = 24
    @Namespace private var ns  // no explicit type needed — always Namespace.ID
    @FocusState private var focused: Bool  // no init(wrappedValue:) — no inline default allowed
    @Query(animation: Animation.bouncy) private var items: [Item]
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var counter = 0
    @SceneStorage("isPinned") private var isPinned = true
    @Binding var isOn: Bool
    var title = "a"
    var subtitle: String? = "x"
    @Bindable var model: Settings
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: Content
}

extension ProfileCard.Core {
    // Gesture wiring is byte-identical to what it would be against the live
    // @GestureState: `dragOffset` reads the mid-gesture value, `$dragOffset`
    // hands `.updating(_:)` the real GestureState<CGSize>. Same for
    // accessibility focus: `$a11yFocused` is a real
    // AccessibilityFocusState<Bool>.Binding, fed to .accessibilityFocused(_:).
    var body: some View {
        Text(colorScheme == .dark ? title.uppercased() : title)
            .font(.system(size: iconSize))
            .offset(dragOffset)
            .gesture(
                DragGesture().updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
            )
            .accessibilityFocused($a11yFocused)
    }
}

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

// Works on an extension — collects COMPUTED members, so stored me/zola/zola2
// don't participate.
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

// Needs only a type, no instance.
let pointFieldNames = Reflector.fieldNames(of: Point.InFlow.self)  // ["x", "y"]
let profileCardFieldNames = Reflector.fieldNames(of: ProfileCard<Text>.InFlow.self)
let profileCardOutFlowFieldNames = Reflector.fieldNames(of: ProfileCard<Text>.OutFlow.self)

// MARK: - OutFlow

var isOnStorage = true
let profileCard = ProfileCard(
    isOn: Binding(get: { isOnStorage }, set: { isOnStorage = $0 }),
    title: "Settings",
    model: Settings(),
    content: { Text("content") },
    footer: { Text("footer") }
)
let profileCardOutFlow = profileCard.outFlow

let profileCardOutFlowFocused = profileCardOutFlow.focused.wrappedValue  // FocusState<Bool>.Binding
let profileCardOutFlowIsPinned = profileCardOutFlow.isPinned.wrappedValue  // Binding<Bool>

// items: QueryCore<[Item]> — wrappedValue/fetchError/modelContext, exactly the
// live @Query's members. Safe outside a live container.
let profileCardOutFlowItems = profileCardOutFlow.items.wrappedValue
let profileCardOutFlowFetchError = profileCardOutFlow.items.fetchError

// MARK: - Core

let profileCardCore = profileCard.core
let profileCardCoreTitle = profileCardCore.title
profileCardCore.isOn = false  // writes straight through to the caller's Binding
let profileCardCoreIsPinned = profileCardCore.isPinned  // bare Bool via @Binding
let profileCardCoreItems = profileCardCore.items  // bare [Item] via @QueryCore — drop-in for @Query
let profileCardCoreSubtitle = profileCardCore.subtitle  // `let` on Core, even though `var` on ProfileCard
let profileCardCoreModel = profileCardCore.model  // @Bindable mirrors verbatim
let profileCardCoreFooter = profileCardCore.footer  // @ViewBuilder stored value → plain let
let profileCardCoreFocused = profileCardCore.focused  // bare Bool via @FocusState<Bool>.Binding
_ = Text("search").focused(profileCardCore.$focused)  // real FocusState<Bool>.Binding
let profileCardCoreDrag = profileCardCore.dragOffset  // bare CGSize via @GestureStateCore
let profileCardCoreA11y = profileCardCore.a11yFocused  // bare Bool via @AccessibilityFocusState<Bool>.Binding
let profileCardCoreIconSize = profileCardCore.iconSize  // bare CGFloat — @ScaledMetric captured as plain let

// Mocking a mid-gesture render: seed a GestureState, wrap it — a
// never-installed GestureState reads back its seed, and @GestureStateCore
// forwards to whatever instance it wraps.
let mockedDrag = GestureStateCore(GestureState(wrappedValue: CGSize(width: 50, height: 7)))
print("mocked mid-gesture value:", mockedDrag.wrappedValue)
