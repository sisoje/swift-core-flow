import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import DataMacrosMacros

final class MemberwiseInitTests: XCTestCase {
    let macros: [String: Macro.Type] = ["MemberwiseInit": MemberwiseInitMacro.self]

    func testPublicStructGetsPublicInit() {
        assertMacroExpansion(
            """
            @MemberwiseInit
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

                    public typealias DataLayout = (UUID, Bool)

                    public static func make(dataLayout: DataLayout) -> Self {
                        Self(id: dataLayout.0, isActive: dataLayout.1)
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
            @MemberwiseInit
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

                    typealias DataLayout = (Int, Int)

                    static func make(dataLayout: DataLayout) -> Self {
                        Self(x: dataLayout.0, y: dataLayout.1)
                    }
                }
                """,
            macros: macros
        )
    }

    func testClassGetsMemberwiseInit() {
        // Works on a class too — e.g. an @Observable class, which Swift gives no
        // memberwise init at all. Access level mirrors the type (internal here).
        // One property collapses DataLayout to its bare type, not a 1-tuple.
        assertMacroExpansion(
            """
            @MemberwiseInit
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

                    typealias DataLayout = Int

                    static func make(dataLayout: DataLayout) -> Self {
                        Self(ii: dataLayout)
                    }
                }
                """,
            macros: macros
        )
    }

    func testActorGetsMemberwiseInit() {
        // Works on an actor too — a synchronous memberwise init is valid (it runs
        // before isolation applies). Access level mirrors the type.
        assertMacroExpansion(
            """
            @MemberwiseInit
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

                    public typealias DataLayout = Int

                    public static func make(dataLayout: DataLayout) -> Self {
                        Self(count: dataLayout)
                    }
                }
                """,
            macros: macros
        )
    }

    func testClosuresGetEscaping() {
        // The init gets @escaping on every function-typed param; the DataLayout
        // typealias never does (a closure nested inside a tuple type is already
        // escaping — @escaping is only legal directly on a function parameter).
        assertMacroExpansion(
            """
            @MemberwiseInit
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

                    public typealias DataLayout = (() -> Void, @MainActor () -> Void, @Sendable (Int) -> Void)

                    public static func make(dataLayout: DataLayout) -> Self {
                        Self(onChange: dataLayout.0, onMain: dataLayout.1, onSend: dataLayout.2)
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
        // attribute to an optional type is a compile error). The DataLayout typealias
        // carries none of these defaults — tuple element types can't have them.
        assertMacroExpansion(
            """
            @MemberwiseInit
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

                    public typealias DataLayout = (String?, (() -> Void)?, (@Sendable (Int) -> Void)!)

                    public static func make(dataLayout: DataLayout) -> Self {
                        Self(nickname: dataLayout.0, onChange: dataLayout.1, onSend: dataLayout.2)
                    }
                }
                """,
            macros: macros
        )
    }

    func testOnlyBindingWrappersReachTheInit() {
        // @Binding is threaded through as Binding<T>; every other wrapper (@State,
        // @Environment, …) is view-owned / injected and excluded — including the
        // untyped `@State private var isExpanded = false`. Binding<T> carries into
        // the DataLayout typealias too.
        assertMacroExpansion(
            """
            @MemberwiseInit
            public struct ProfileCard: View {
                @Environment(\\.colorScheme) private var colorScheme
                @Binding public var isOn: Bool
                @State private var isExpanded = false
                public let title: String
            }
            """,
            expandedSource: """
                public struct ProfileCard: View {
                    @Environment(\\.colorScheme) private var colorScheme
                    @Binding public var isOn: Bool
                    @State private var isExpanded = false
                    public let title: String

                    public init(isOn: Binding<Bool>, title: String) {
                        self._isOn = isOn
                        self.title = title
                    }

                    public typealias DataLayout = (Binding<Bool>, String)

                    public static func make(dataLayout: DataLayout) -> Self {
                        Self(isOn: dataLayout.0, title: dataLayout.1)
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
        // DataLayout collapses to its bare type.
        assertMacroExpansion(
            """
            @MemberwiseInit
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

                    public typealias DataLayout = String

                    public static func make(dataLayout: DataLayout) -> Self {
                        Self(title: dataLayout)
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
        // (self.footer = footer()). The DataLayout typealias ignores @ViewBuilder
        // entirely: footer keeps its own type (Content), not a builder closure —
        // there's no parameter position inside a tuple type for the trailing-closure
        // sugar wrapping exists to enable, and a closure isn't Equatable/storable.
        // make(dataLayout:) re-wraps footer into a trivial closure to satisfy the
        // init, reading it positionally (dataLayout.2) since DataLayout is unlabeled.
        assertMacroExpansion(
            """
            @MemberwiseInit
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

                    public typealias DataLayout = (String, () -> Content, Content)

                    public static func make(dataLayout: DataLayout) -> Self {
                        Self(title: dataLayout.0, content: dataLayout.1, footer: {
                                dataLayout.2
                            })
                    }
                }
                """,
            macros: macros
        )
    }

    func testComputedAndStaticAreSkipped() {
        assertMacroExpansion(
            """
            @MemberwiseInit
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

                    public typealias DataLayout = (Double, Double)

                    public static func make(dataLayout: DataLayout) -> Self {
                        Self(x: dataLayout.0, y: dataLayout.1)
                    }
                }
                """,
            macros: macros
        )
    }

    func testOnePropertyCollapsesDataLayoutToItsBareType() {
        // No 1-tuples in Swift, so (value: Int) as a type is just Int — and
        // make(dataLayout:) takes it as that bare value directly (no positional
        // index needed either, unlike the tuple case).
        assertMacroExpansion(
            """
            @MemberwiseInit
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

                    public typealias DataLayout = Int

                    public static func make(dataLayout: DataLayout) -> Self {
                        Self(value: dataLayout)
                    }
                }
                """,
            macros: macros
        )
    }

    func testTwoPropertiesGetATupleDataLayout() {
        assertMacroExpansion(
            """
            @MemberwiseInit
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

                    public typealias DataLayout = (Int, Int)

                    public static func make(dataLayout: DataLayout) -> Self {
                        Self(x: dataLayout.0, y: dataLayout.1)
                    }
                }
                """,
            macros: macros
        )
    }

    func testDiagnosesNotAStruct() {
        assertMacroExpansion(
            """
            @MemberwiseInit
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
                    message: "@MemberwiseInit can only be attached to a struct, class, or actor.",
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
            @MemberwiseInit
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
                        "Stored property 'count' needs an explicit type annotation so @MemberwiseInit can generate the initializer.",
                    line: 3,
                    column: 16
                )
            ],
            macros: macros
        )
    }
}
