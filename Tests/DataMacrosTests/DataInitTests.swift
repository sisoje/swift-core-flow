import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import DataMacrosMacros

final class DataInitTests: XCTestCase {
    let macros: [String: Macro.Type] = ["DataInit": DataInitMacro.self]

    func testGeneratesBothThePerPropertyInitAndTheDataLayoutInit() {
        assertMacroExpansion(
            """
            @DataInit
            public struct User {
                public let id: UUID
                public let name: String
            }
            """,
            expandedSource: """
                public struct User {
                    public let id: UUID
                    public let name: String

                    public init(id: UUID, name: String) {
                        self.id = id
                        self.name = name
                    }

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

    func testSinglePropertyGetsBothAnUnlabeledAndALabeledInitPlusABareTypeDataLayout() {
        // Distinct signatures (label vs. no label) so both coexist even though
        // there's only one property. DataLayout still gets generated — just as an
        // alias for the bare field type, not a 1-tuple (Swift doesn't have those).
        assertMacroExpansion(
            """
            @DataInit
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

                    public init(_ value: DataLayout) {
                        self.value = value
                    }
                }
                """,
            macros: macros
        )
    }

    func testNoPropertiesGetsOneSharedEmptyInitNotADuplicate() {
        // Both renderers would independently produce `init() {}` — collapsed to one
        // to avoid "invalid redeclaration of 'init()'".
        assertMacroExpansion(
            """
            @DataInit
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

    func testAccessLevelMirrorsTheTypeOnBothInits() {
        assertMacroExpansion(
            """
            @DataInit
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

    func testBindingIsThreadedConsistentlyIntoBothInits() {
        assertMacroExpansion(
            """
            @DataInit
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

                    public init(isOn: Binding<Bool>, title: String) {
                        self._isOn = isOn
                        self.title = title
                    }

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

    func testMissingTypeIsDiagnosedOnceNotTwice() {
        // The whole point of @DataInit over stacking @DataLayoutInit @MemberwiseInit:
        // one collection pass, so a bad property is flagged once.
        assertMacroExpansion(
            """
            @DataInit
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
                        "Stored property 'count' needs an explicit type annotation so @DataInit can generate the initializer.",
                    line: 3,
                    column: 16
                )
            ],
            macros: macros
        )
    }

    // testDiagnosesNotAStruct is intentionally not repeated here — it exercises
    // validatedProperties's type guard, which is macro-agnostic and already covered
    // by MemberwiseInitTests. testMissingTypeIsDiagnosedOnceNotTwice above is this
    // suite's diagnostic coverage that's actually specific to @DataInit.
}
