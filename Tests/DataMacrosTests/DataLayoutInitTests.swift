import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import DataMacrosMacros

final class DataLayoutInitTests: XCTestCase {
    let macros: [String: Macro.Type] = ["DataLayoutInit": DataLayoutInitMacro.self]

    func testMultiplePropertiesGetATupleDataLayoutAndInit() {
        assertMacroExpansion(
            """
            @DataLayoutInit
            public struct User {
                public let id: UUID
                public let name: String
            }
            """,
            expandedSource: """
                public struct User {
                    public let id: UUID
                    public let name: String

                    public typealias DataLayout = (id: UUID, name: String)

                    public init(_ dataLayout: DataLayout) {
                        self.id = dataLayout.id
                        self.name = dataLayout.name
                    }
                }
                """,
            macros: macros
        )
    }

    func testSinglePropertyGetsABareTypeDataLayoutNotATuple() {
        // Swift has no 1-tuples — (value: Int) as a type collapses to plain Int, no
        // .value accessor — so DataLayout aliases the bare field type directly, and
        // the init skips routing through it: same shape @MemberwiseInit would
        // produce for one property, just unlabeled.
        assertMacroExpansion(
            """
            @DataLayoutInit
            public struct Box {
                public let value: Int
            }
            """,
            expandedSource: """
                public struct Box {
                    public let value: Int

                    public typealias DataLayout = Int

                    public init(_ value: DataLayout) {
                        self.value = value
                    }
                }
                """,
            macros: macros
        )
    }

    func testNoPropertiesGetsAnEmptyInit() {
        assertMacroExpansion(
            """
            @DataLayoutInit
            struct Empty {}
            """,
            expandedSource: """
                struct Empty {

                    init() {
                    }
                }
                """,
            macros: macros
        )
    }

    func testAccessLevelMirrorsTheType() {
        assertMacroExpansion(
            """
            @DataLayoutInit
            struct Point {
                let x: Int
                let y: Int
            }
            """,
            expandedSource: """
                struct Point {
                    let x: Int
                    let y: Int

                    typealias DataLayout = (x: Int, y: Int)

                    init(_ dataLayout: DataLayout) {
                        self.x = dataLayout.x
                        self.y = dataLayout.y
                    }
                }
                """,
            macros: macros
        )
    }

    func testClassGetsDataLayoutInit() {
        assertMacroExpansion(
            """
            @DataLayoutInit
            @Observable final class Zola {
                var ii: Int = 0
                var jj: Int = 0
            }
            """,
            expandedSource: """
                @Observable final class Zola {
                    var ii: Int = 0
                    var jj: Int = 0

                    typealias DataLayout = (ii: Int, jj: Int)

                    init(_ dataLayout: DataLayout) {
                        self.ii = dataLayout.ii
                        self.jj = dataLayout.jj
                    }
                }
                """,
            macros: macros
        )
    }

    func testInlineDefaultsAreDroppedTupleFieldsCantCarryThem() {
        // Unlike @MemberwiseInit, a var's inline default (or optional-implies-nil)
        // does NOT carry through — tuple element types can't have `= default`.
        assertMacroExpansion(
            """
            @DataLayoutInit
            public struct Handler {
                public var count: Int = 0
                public var nickname: String?
            }
            """,
            expandedSource: """
                public struct Handler {
                    public var count: Int = 0
                    public var nickname: String?

                    public typealias DataLayout = (count: Int, nickname: String?)

                    public init(_ dataLayout: DataLayout) {
                        self.count = dataLayout.count
                        self.nickname = dataLayout.nickname
                    }
                }
                """,
            macros: macros
        )
    }

    func testBindingIsThreadedAsProjectedBindingField() {
        assertMacroExpansion(
            """
            @DataLayoutInit
            public struct ProfileCard: View {
                @Environment(\\.colorScheme) private var colorScheme
                @Binding public var isOn: Bool
                public let title: String
            }
            """,
            expandedSource: """
                public struct ProfileCard: View {
                    @Environment(\\.colorScheme) private var colorScheme
                    @Binding public var isOn: Bool
                    public let title: String

                    public typealias DataLayout = (isOn: Binding<Bool>, title: String)

                    public init(_ dataLayout: DataLayout) {
                        self._isOn = dataLayout.isOn
                        self.title = dataLayout.title
                    }
                }
                """,
            macros: macros
        )
    }

    func testFunctionTypedFieldGetsNoEscapingItsAlreadyImplicitInsideTheTuple() {
        assertMacroExpansion(
            """
            @DataLayoutInit
            public struct Handler {
                public var onChange: () -> Void
                public var onSend: @Sendable (Int) -> Void
            }
            """,
            expandedSource: """
                public struct Handler {
                    public var onChange: () -> Void
                    public var onSend: @Sendable (Int) -> Void

                    public typealias DataLayout = (onChange: () -> Void, onSend: @Sendable (Int) -> Void)

                    public init(_ dataLayout: DataLayout) {
                        self.onChange = dataLayout.onChange
                        self.onSend = dataLayout.onSend
                    }
                }
                """,
            macros: macros
        )
    }

    func testViewBuilderStoredValueFieldIsCalledLikeMemberwiseInit() {
        assertMacroExpansion(
            """
            @DataLayoutInit
            public struct Card<Content: View>: View {
                public let title: String
                @ViewBuilder let footer: Content
            }
            """,
            expandedSource: """
                public struct Card<Content: View>: View {
                    public let title: String
                    @ViewBuilder let footer: Content

                    public typealias DataLayout = (title: String, footer: () -> Content)

                    public init(_ dataLayout: DataLayout) {
                        self.title = dataLayout.title
                        self.footer = dataLayout.footer()
                    }
                }
                """,
            macros: macros
        )
    }

    func testPrivatePropertiesAreExcluded() {
        assertMacroExpansion(
            """
            @DataLayoutInit
            public struct V {
                public var title: String
                public var count: Int
                private var cache: Int = 0
            }
            """,
            expandedSource: """
                public struct V {
                    public var title: String
                    public var count: Int
                    private var cache: Int = 0

                    public typealias DataLayout = (title: String, count: Int)

                    public init(_ dataLayout: DataLayout) {
                        self.title = dataLayout.title
                        self.count = dataLayout.count
                    }
                }
                """,
            macros: macros
        )
    }

    // testComputedAndStaticAreSkipped and testDiagnosesNotAStruct are intentionally
    // not repeated here — both exercise shared, macro-agnostic logic
    // (collectStoredProperties's skip rules, validatedProperties's type guard) that
    // MemberwiseInitTests already covers; this file's tests instead focus on what's
    // actually specific to DataLayoutInit's rendering.

    func testDiagnosesMissingType() {
        assertMacroExpansion(
            """
            @DataLayoutInit
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
                        "Stored property 'count' needs an explicit type annotation so @DataLayoutInit can generate the initializer.",
                    line: 3,
                    column: 16
                )
            ],
            macros: macros
        )
    }
}
