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
                }
                """,
            macros: macros
        )
    }

    func testAccessLevelMirrorsTheStruct() {
        // A plain (internal) struct gets an init with no access modifier.
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
                }
                """,
            macros: macros
        )
    }

    func testClassGetsMemberwiseInit() {
        // Works on a class too — e.g. an @Observable class, which Swift gives no
        // memberwise init at all. Access level mirrors the type (internal here).
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
                }
                """,
            macros: macros
        )
    }

    func testClosuresGetEscaping() {
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
                }
                """,
            macros: macros
        )
    }

    func testOptionalVarsAreImplicitlyNilDefaulted() {
        // An optional `var` is implicitly nil-initialized, so its parameter defaults
        // to nil — just like Swift's own memberwise init. Optional closures also get
        // no @escaping (an optional parameter is already escaping; adding the
        // attribute to an optional type is a compile error).
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
                }
                """,
            macros: macros
        )
    }

    func testOnlyBindingWrappersReachTheInit() {
        // @Binding is threaded through as Binding<T>; every other wrapper (@State,
        // @Environment, …) is view-owned / injected and excluded — including the
        // untyped `@State private var isExpanded = false`.
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
                }
                """,
            macros: macros
        )
    }

    func testPrivatePropertiesAreExcluded() {
        // Every private/fileprivate stored property is kept out of the init — private
        // state is an implementation detail, not part of the init surface.
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
                }
                """,
            macros: macros
        )
    }

    func testViewBuilderPropertiesGetBuilderParameters() {
        // @ViewBuilder carries onto the parameter. A stored closure (() -> Content)
        // becomes an @escaping builder closure; a stored value (Content) becomes a
        // () -> Content builder the init calls (self.footer = footer()).
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
