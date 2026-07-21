import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import ValueFlowMacros

final class DataLayoutTests: XCTestCase {
    let macros: [String: Macro.Type] = ["DataLayout": DataLayoutMacro.self]

    func testPublicStructGetsPublicInit() {
        assertMacroExpansion(
            """
            @DataLayout
            public struct User {
                public let id: UUID
                public var isActive: Bool = false
            }
            """,
            expandedSource: """
                public struct User {
                    public let id: UUID
                    public var isActive: Bool = false

                    public init(id: UUID, isActive: Bool = false) {
                        self.id = id
                        self.isActive = isActive
                    }

                    public typealias InFlowSplat = (UUID, Bool)

                    public static func makeFlow(_ flow: InFlowSplat) -> Self {
                        Self(id: flow.0, isActive: flow.1)
                    }

                    public typealias InFlow = (id: UUID, isActive: Bool)

                    public var inFlow: InFlow {
                        (id: self.id, isActive: self.isActive)
                    }

                    public typealias OutFlow = (id: UUID, isActive: Bool)

                    public var outFlow: OutFlow {
                        (id: self.id, isActive: self.isActive)
                    }
                }
                """,
            macros: macros
        )
    }

    func testAccessLevelMirrorsTheStruct() {
        // A plain (internal) struct gets an init and typealias with no access modifier.
        assertMacroExpansion(
            """
            @DataLayout
            struct Point {
                let x: Int
                let y: Int
            }
            """,
            expandedSource: """
                struct Point {
                    let x: Int
                    let y: Int

                    init(x: Int, y: Int) {
                        self.x = x
                        self.y = y
                    }

                    typealias InFlowSplat = (Int, Int)

                    static func makeFlow(_ flow: InFlowSplat) -> Self {
                        Self(x: flow.0, y: flow.1)
                    }

                    typealias InFlow = (x: Int, y: Int)

                    var inFlow: InFlow {
                        (x: self.x, y: self.y)
                    }

                    typealias OutFlow = (x: Int, y: Int)

                    var outFlow: OutFlow {
                        (x: self.x, y: self.y)
                    }
                }
                """,
            macros: macros
        )
    }

    func testWorksOnAClass() {
        // Works on a class too — e.g. an @Observable class, which Swift gives no
        // memberwise init at all. Access level mirrors the type (internal here).
        // One property collapses InFlowSplat to its bare type, not a 1-tuple.
        assertMacroExpansion(
            """
            @DataLayout
            @Observable final class Zola {
                var ii: Int = 0
            }
            """,
            expandedSource: """
                @Observable final class Zola {
                    var ii: Int = 0

                    init(ii: Int = 0) {
                        self.ii = ii
                    }

                    typealias InFlowSplat = Int

                    static func makeFlow(_ flow: InFlowSplat) -> Self {
                        Self(ii: flow)
                    }

                    typealias InFlow = Int

                    var inFlow: InFlow {
                        self.ii
                    }

                    typealias OutFlow = Int

                    var outFlow: OutFlow {
                        self.ii
                    }
                }
                """,
            macros: macros
        )
    }

    func testWorksOnAnActor() {
        // Works on an actor too — a synchronous memberwise init is valid (it runs
        // before isolation applies). Access level mirrors the type.
        assertMacroExpansion(
            """
            @DataLayout
            public actor Counter {
                public var count: Int = 0
            }
            """,
            expandedSource: """
                public actor Counter {
                    public var count: Int = 0

                    public init(count: Int = 0) {
                        self.count = count
                    }

                    public typealias InFlowSplat = Int

                    public static func makeFlow(_ flow: InFlowSplat) -> Self {
                        Self(count: flow)
                    }

                    public typealias InFlow = Int

                    public var inFlow: InFlow {
                        self.count
                    }

                    public typealias OutFlow = Int

                    public var outFlow: OutFlow {
                        self.count
                    }
                }
                """,
            macros: macros
        )
    }

    func testClosuresGetEscaping() {
        // The init gets @escaping on every function-typed param; the InFlowSplat
        // typealias never does (a closure nested inside a tuple type is already
        // escaping — @escaping is only legal directly on a function parameter).
        assertMacroExpansion(
            """
            @DataLayout
            public struct Handler {
                public var onChange: () -> Void
                public var onMain: @MainActor () -> Void
                public var onSend: @Sendable (Int) -> Void
            }
            """,
            expandedSource: """
                public struct Handler {
                    public var onChange: () -> Void
                    public var onMain: @MainActor () -> Void
                    public var onSend: @Sendable (Int) -> Void

                    public init(onChange: @escaping () -> Void, onMain: @escaping @MainActor () -> Void, onSend: @escaping @Sendable (Int) -> Void) {
                        self.onChange = onChange
                        self.onMain = onMain
                        self.onSend = onSend
                    }

                    public typealias InFlowSplat = (() -> Void, @MainActor () -> Void, @Sendable (Int) -> Void)

                    public static func makeFlow(_ flow: InFlowSplat) -> Self {
                        Self(onChange: flow.0, onMain: flow.1, onSend: flow.2)
                    }

                    public typealias InFlow = (onChange: () -> Void, onMain: @MainActor () -> Void, onSend: @Sendable (Int) -> Void)

                    public var inFlow: InFlow {
                        (onChange: self.onChange, onMain: self.onMain, onSend: self.onSend)
                    }

                    public typealias OutFlow = (onChange: () -> Void, onMain: @MainActor () -> Void, onSend: @Sendable (Int) -> Void)

                    public var outFlow: OutFlow {
                        (onChange: self.onChange, onMain: self.onMain, onSend: self.onSend)
                    }
                }
                """,
            macros: macros
        )
    }

    func testOptionalVarsAreImplicitlyNilDefaulted() {
        // An optional `var` is implicitly nil-initialized, so its parameter defaults
        // to nil — just like Swift's own memberwise init. Optional closures also get
        // no @escaping (an optional parameter is already escaping; adding the
        // attribute to an optional type is a compile error). The InFlowSplat typealias
        // carries none of these defaults — tuple element types can't have them.
        assertMacroExpansion(
            """
            @DataLayout
            public struct Handler {
                public var nickname: String?
                public var onChange: (() -> Void)?
                public var onSend: (@Sendable (Int) -> Void)!
            }
            """,
            expandedSource: """
                public struct Handler {
                    public var nickname: String?
                    public var onChange: (() -> Void)?
                    public var onSend: (@Sendable (Int) -> Void)!

                    public init(nickname: String? = nil, onChange: (() -> Void)? = nil, onSend: (@Sendable (Int) -> Void)! = nil) {
                        self.nickname = nickname
                        self.onChange = onChange
                        self.onSend = onSend
                    }

                    public typealias InFlowSplat = (String?, (() -> Void)?, (@Sendable (Int) -> Void)!)

                    public static func makeFlow(_ flow: InFlowSplat) -> Self {
                        Self(nickname: flow.0, onChange: flow.1, onSend: flow.2)
                    }

                    public typealias InFlow = (nickname: String?, onChange: (() -> Void)?, onSend: (@Sendable (Int) -> Void)!)

                    public var inFlow: InFlow {
                        (nickname: self.nickname, onChange: self.onChange, onSend: self.onSend)
                    }

                    public typealias OutFlow = (nickname: String?, onChange: (() -> Void)?, onSend: (@Sendable (Int) -> Void)!)

                    public var outFlow: OutFlow {
                        (nickname: self.nickname, onChange: self.onChange, onSend: self.onSend)
                    }
                }
                """,
            macros: macros
        )
    }

    func testOnlyBindingWrappersReachTheInit() {
        // @Binding is threaded through as Binding<T>; every other wrapper (@State,
        // @Environment, …) is excluded from the INIT — but @Environment/@State
        // still need an explicit type even though private: @Environment because
        // @StatelessNode (a separate macro) mirrors it verbatim, @State because it's
        // one of OutFlow's recognized wrapper kinds. OutFlow itself no longer
        // includes @Environment at all (see below) — only @State/@AppStorage/
        // @Query, plus non-private fields.
        // Binding<T> carries into the InFlowSplat typealias too, and the inFlow
        // property reads its projected form (self._isOn), not the wrapped Bool
        // value — OutFlow reads isOn the same way (it's non-private), but reads
        // isExpanded via its OWN projected form (self.$isExpanded), since @State's
        // wrapper instance (self._isExpanded) is a State<Bool>, not a Binding<Bool>.
        assertMacroExpansion(
            """
            @DataLayout
            public struct ProfileCard: View {
                @Environment(\\.colorScheme) private var colorScheme: ColorScheme
                @Binding public var isOn: Bool
                @State private var isExpanded: Bool = false
                public let title: String
            }
            """,
            expandedSource: """
                public struct ProfileCard: View {
                    @Environment(\\.colorScheme) private var colorScheme: ColorScheme
                    @Binding public var isOn: Bool
                    @State private var isExpanded: Bool = false
                    public let title: String

                    public init(isOn: Binding<Bool>, title: String) {
                        self._isOn = isOn
                        self.title = title
                    }

                    public typealias InFlowSplat = (Binding<Bool>, String)

                    public static func makeFlow(_ flow: InFlowSplat) -> Self {
                        Self(isOn: flow.0, title: flow.1)
                    }

                    public typealias InFlow = (isOn: Binding<Bool>, title: String)

                    public var inFlow: InFlow {
                        (isOn: self._isOn, title: self.title)
                    }

                    public typealias OutFlow = (isOn: Binding<Bool>, isExpanded: Binding<Bool>, title: String)

                    public var outFlow: OutFlow {
                        (isOn: self._isOn, isExpanded: self.$isExpanded, title: self.title)
                    }
                }
                """,
            macros: macros
        )
    }

    func testPrivatePropertiesAreExcluded() {
        // Every private/fileprivate stored property is kept out of both the init and
        // the typealias — private state is an implementation detail, not part of the
        // public surface either way. Only one property (title) survives, so
        // InFlowSplat collapses to its bare type.
        assertMacroExpansion(
            """
            @DataLayout
            public struct V {
                public var title: String
                private var cache: Int = 0
                fileprivate var scratch = ""
                private let seed = 42
            }
            """,
            expandedSource: """
                public struct V {
                    public var title: String
                    private var cache: Int = 0
                    fileprivate var scratch = ""
                    private let seed = 42

                    public init(title: String) {
                        self.title = title
                    }

                    public typealias InFlowSplat = String

                    public static func makeFlow(_ flow: InFlowSplat) -> Self {
                        Self(title: flow)
                    }

                    public typealias InFlow = String

                    public var inFlow: InFlow {
                        self.title
                    }

                    public typealias OutFlow = String

                    public var outFlow: OutFlow {
                        self.title
                    }
                }
                """,
            macros: macros
        )
    }

    func testViewBuilderPropertiesGetBuilderParameters() {
        // @ViewBuilder carries onto the init parameter. A stored closure
        // (() -> Content) becomes an @escaping builder closure; a stored value
        // (Content) becomes a () -> Content builder the init calls
        // (self.footer = footer()). The InFlowSplat typealias ignores @ViewBuilder
        // entirely: footer keeps its own type (Content), not a builder closure —
        // there's no parameter position inside a tuple type for the trailing-closure
        // sugar wrapping exists to enable, and a closure isn't Equatable/storable.
        // makeFlow(_:) re-wraps footer into a trivial closure to satisfy the
        // init, reading it positionally (flow.2) since InFlowSplat is unlabeled.
        // The inFlow property is the reverse: it reads self.footer directly, no
        // wrapping needed — the stored property already holds the plain Content
        // value regardless of what the init's parameter looks like.
        assertMacroExpansion(
            """
            @DataLayout
            public struct ProfileCard<Content: View>: View {
                public let title: String
                @ViewBuilder let content: () -> Content
                @ViewBuilder let footer: Content
            }
            """,
            expandedSource: """
                public struct ProfileCard<Content: View>: View {
                    public let title: String
                    @ViewBuilder let content: () -> Content
                    @ViewBuilder let footer: Content

                    public init(title: String, @ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: () -> Content) {
                        self.title = title
                        self.content = content
                        self.footer = footer()
                    }

                    public typealias InFlowSplat = (String, () -> Content, Content)

                    public static func makeFlow(_ flow: InFlowSplat) -> Self {
                        Self(title: flow.0, content: flow.1, footer: {
                                flow.2
                            })
                    }

                    public typealias InFlow = (title: String, content: () -> Content, footer: Content)

                    public var inFlow: InFlow {
                        (title: self.title, content: self.content, footer: self.footer)
                    }

                    public typealias OutFlow = (title: String, content: () -> Content, footer: Content)

                    public var outFlow: OutFlow {
                        (title: self.title, content: self.content, footer: self.footer)
                    }
                }
                """,
            macros: macros
        )
    }

    func testComputedAndStaticAreSkipped() {
        assertMacroExpansion(
            """
            @DataLayout
            public struct Point {
                public let x: Double
                public let y: Double
                public static let origin = Point(x: 0, y: 0)
                public var magnitude: Double { (x * x + y * y).squareRoot() }
            }
            """,
            expandedSource: """
                public struct Point {
                    public let x: Double
                    public let y: Double
                    public static let origin = Point(x: 0, y: 0)
                    public var magnitude: Double { (x * x + y * y).squareRoot() }

                    public init(x: Double, y: Double) {
                        self.x = x
                        self.y = y
                    }

                    public typealias InFlowSplat = (Double, Double)

                    public static func makeFlow(_ flow: InFlowSplat) -> Self {
                        Self(x: flow.0, y: flow.1)
                    }

                    public typealias InFlow = (x: Double, y: Double)

                    public var inFlow: InFlow {
                        (x: self.x, y: self.y)
                    }

                    public typealias OutFlow = (x: Double, y: Double)

                    public var outFlow: OutFlow {
                        (x: self.x, y: self.y)
                    }
                }
                """,
            macros: macros
        )
    }

    func testOnePropertyCollapsesInFlowSplatToItsBareType() {
        // No 1-tuples in Swift, so (value: Int) as a type is just Int — and
        // makeFlow(_:) takes it as that bare value directly (no positional
        // index needed either, unlike the tuple case). Same collapse for
        // InFlow, since there's no label left to preserve either.
        assertMacroExpansion(
            """
            @DataLayout
            public struct Box {
                public let value: Int
            }
            """,
            expandedSource: """
                public struct Box {
                    public let value: Int

                    public init(value: Int) {
                        self.value = value
                    }

                    public typealias InFlowSplat = Int

                    public static func makeFlow(_ flow: InFlowSplat) -> Self {
                        Self(value: flow)
                    }

                    public typealias InFlow = Int

                    public var inFlow: InFlow {
                        self.value
                    }

                    public typealias OutFlow = Int

                    public var outFlow: OutFlow {
                        self.value
                    }
                }
                """,
            macros: macros
        )
    }

    func testTwoPropertiesGetATupleInFlowSplat() {
        assertMacroExpansion(
            """
            @DataLayout
            public struct Point {
                public let x: Int
                public let y: Int
            }
            """,
            expandedSource: """
                public struct Point {
                    public let x: Int
                    public let y: Int

                    public init(x: Int, y: Int) {
                        self.x = x
                        self.y = y
                    }

                    public typealias InFlowSplat = (Int, Int)

                    public static func makeFlow(_ flow: InFlowSplat) -> Self {
                        Self(x: flow.0, y: flow.1)
                    }

                    public typealias InFlow = (x: Int, y: Int)

                    public var inFlow: InFlow {
                        (x: self.x, y: self.y)
                    }

                    public typealias OutFlow = (x: Int, y: Int)

                    public var outFlow: OutFlow {
                        (x: self.x, y: self.y)
                    }
                }
                """,
            macros: macros
        )
    }

    func testZeroPropertiesGeneratesOnlyTheBareInit() {
        // Nothing to alias/build from — InFlowSplat/InFlow/OutFlow all
        // collapse together with the same "at least one participating property"
        // rule, so a zero-property type gets only the bare init, nothing else.
        assertMacroExpansion(
            """
            @DataLayout
            public struct Empty {
            }
            """,
            expandedSource: """
                public struct Empty {

                    public init() {

                    }
                }
                """,
            macros: macros
        )
    }

    func testOutFlowSynthesizesQueryAsAResultFetchErrorModelContextTuple() {
        // @Query is NOT a passthrough of its declared type the way @Environment
        // is — OutFlow always synthesizes (result: WrappedType, fetchError: Error?,
        // modelContext: ModelContext). fetchError/modelContext are real members of
        // SwiftData's Query wrapper *instance* (verified directly against the
        // SwiftData interface: `@MainActor @preconcurrency public var fetchError:
        // (any Error)? { get }`, `public var modelContext: ModelContext { get }`),
        // reached via the underscore-prefixed backing storage — not synthesized
        // placeholders.
        assertMacroExpansion(
            """
            @DataLayout
            public struct ItemList {
                @Query private var items: [Item]
                public let title: String
            }
            """,
            expandedSource: """
                public struct ItemList {
                    @Query private var items: [Item]
                    public let title: String

                    public init(title: String) {
                        self.title = title
                    }

                    public typealias InFlowSplat = String

                    public static func makeFlow(_ flow: InFlowSplat) -> Self {
                        Self(title: flow)
                    }

                    public typealias InFlow = String

                    public var inFlow: InFlow {
                        self.title
                    }

                    public typealias OutFlow = (items: (result: [Item], fetchError: Error?, modelContext: ModelContext), title: String)

                    public var outFlow: OutFlow {
                        (items: (result: self.items, fetchError: self._items.fetchError, modelContext: self._items.modelContext), title: self.title)
                    }
                }
                """,
            macros: macros
        )
    }

    func testOutFlowReadsFocusStateAsItsOwnProjectedBindingTypeNotBindingT() {
        // @FocusState reads via the same `self.$x` shortcut @State/@AppStorage
        // use, but resolves to a genuinely different type: FocusState<T>.Binding,
        // not Binding<T> — verified directly against the real SwiftUI interface
        // that FocusState<T>.Binding has no public conversion to Binding<T> (and
        // no public initializer at all), so it's kept as its own distinct
        // mapping rather than folded into @State/@AppStorage's.
        assertMacroExpansion(
            """
            @DataLayout
            public struct SearchField {
                @FocusState private var isFocused: Bool
                public let title: String
            }
            """,
            expandedSource: """
                public struct SearchField {
                    @FocusState private var isFocused: Bool
                    public let title: String

                    public init(title: String) {
                        self.title = title
                    }

                    public typealias InFlowSplat = String

                    public static func makeFlow(_ flow: InFlowSplat) -> Self {
                        Self(title: flow)
                    }

                    public typealias InFlow = String

                    public var inFlow: InFlow {
                        self.title
                    }

                    public typealias OutFlow = (isFocused: FocusState<Bool>.Binding, title: String)

                    public var outFlow: OutFlow {
                        (isFocused: self.$isFocused, title: self.title)
                    }
                }
                """,
            macros: macros
        )
    }

    func testOutFlowFoldsSceneStorageIntoTheSameBindingMappingAsAppStorage() {
        // @SceneStorage's own wrappedValue is get/nonmutating-set and its
        // projectedValue genuinely IS Binding<T> — verified directly against
        // the real SwiftUI interface, the same shape @State/@AppStorage have —
        // so it folds into their exact mapping, no separate case needed
        // (unlike @FocusState, which genuinely can't share it).
        assertMacroExpansion(
            """
            @DataLayout
            public struct SearchField {
                @SceneStorage("isPinned") private var isPinned: Bool = false
                public let title: String
            }
            """,
            expandedSource: """
                public struct SearchField {
                    @SceneStorage("isPinned") private var isPinned: Bool = false
                    public let title: String

                    public init(title: String) {
                        self.title = title
                    }

                    public typealias InFlowSplat = String

                    public static func makeFlow(_ flow: InFlowSplat) -> Self {
                        Self(title: flow)
                    }

                    public typealias InFlow = String

                    public var inFlow: InFlow {
                        self.title
                    }

                    public typealias OutFlow = (isPinned: Binding<Bool>, title: String)

                    public var outFlow: OutFlow {
                        (isPinned: self.$isPinned, title: self.title)
                    }
                }
                """,
            macros: macros
        )
    }

    func testDiagnosesNotAStruct() {
        assertMacroExpansion(
            """
            @DataLayout
            public enum E {
                case a
            }
            """,
            expandedSource: """
                public enum E {
                    case a
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@DataLayout can only be attached to a struct, class, or actor.",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }

    func testDiagnosesMissingType() {
        assertMacroExpansion(
            """
            @DataLayout
            public struct Thing {
                public var count = 0
            }
            """,
            expandedSource: """
                public struct Thing {
                    public var count = 0
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "Stored property 'count' needs an explicit type annotation so @DataLayout can generate the initializer/stateless snapshot.",
                    line: 3,
                    column: 16
                )
            ],
            macros: macros
        )
    }

    func testDiagnosesNonPrivateSourceOfTruthWrappers() {
        // @State/@Environment/@Query/@AppStorage/@SceneStorage/@FocusState/
        // @Namespace are a view's own source of truth, never something a
        // caller supplies — enforced here rather than accommodated: every
        // downstream renderer can assume these seven are always private, with
        // no "what if it's also public" case to handle.
        assertMacroExpansion(
            """
            @DataLayout
            struct Card {
                @State var isExpanded = false
            }
            """,
            expandedSource: """
                struct Card {
                    @State var isExpanded = false
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "'isExpanded' must be private — @State/@Environment/@Query/@AppStorage/@SceneStorage/@FocusState/@Namespace are a view's own source of truth, not something a caller supplies (use @Binding for that).",
                    line: 3,
                    column: 16
                )
            ],
            macros: macros
        )
    }
}
