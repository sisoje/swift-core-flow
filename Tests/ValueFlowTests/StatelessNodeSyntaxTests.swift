import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import ValueFlowMacros

final class StatelessNodeSyntaxTests: XCTestCase {
    let macros: [String: Macro.Type] = ["StatelessNode": StatelessNodeMacro.self]

    func testMixOfPlainQueryEnvironmentStateAndBindingFields() {
        assertMacroExpansion(
            """
            @StatelessNode
            struct Card {
                @Query private var items: [Item]
                @Environment(\\.colorScheme) private var colorScheme: ColorScheme
                @State private var isExpanded: Bool = false
                @Binding var isOn: Bool
                let title: String
            }
            """,
            expandedSource: """
                struct Card {
                    @Query private var items: [Item]
                    @Environment(\\.colorScheme) private var colorScheme: ColorScheme
                    @State private var isExpanded: Bool = false
                    @Binding var isOn: Bool
                    let title: String

                    @DataLayout
                    struct StatelessNode {
                        var items: (result: [Item], fetchError: Error?, modelContext: ModelContext)
                        let colorScheme: ColorScheme
                        @Binding var isExpanded: Bool
                        @Binding var isOn: Bool
                        let title: String
                    }

                    var statelessNode: StatelessNode {
                        StatelessNode(items: (result: self.items, fetchError: self._items.fetchError, modelContext: self._items.modelContext), colorScheme: self.colorScheme, isExpanded: self.$isExpanded, isOn: self._isOn, title: self.title)
                    }
                }
                """,
            macros: macros
        )
    }

    func testZeroEligibleFieldsStillGeneratesAnEmptyStatelessNodeStruct() {
        assertMacroExpansion(
            """
            @StatelessNode
            struct Empty {
                private var cache = 0
            }
            """,
            expandedSource: """
                struct Empty {
                    private var cache = 0

                    @DataLayout
                    struct StatelessNode {

                    }

                    var statelessNode: StatelessNode {
                        StatelessNode()
                    }
                }
                """,
            macros: macros
        )
    }

    func testViewBuilderAndBindablePropertiesMirrorVerbatimIncludingLetVsVar() {
        assertMacroExpansion(
            """
            @StatelessNode
            struct ProfileCard<Content: View> {
                var subtitle: String?
                @Bindable var model: Settings
                @ViewBuilder let content: () -> Content
                @ViewBuilder let footer: Content
            }
            """,
            expandedSource: """
                struct ProfileCard<Content: View> {
                    var subtitle: String?
                    @Bindable var model: Settings
                    @ViewBuilder let content: () -> Content
                    @ViewBuilder let footer: Content

                    @DataLayout
                    struct StatelessNode {
                        var subtitle: String?
                        @Bindable var model: Settings
                        @ViewBuilder let content: () -> Content
                        @ViewBuilder let footer: Content
                    }

                    var statelessNode: StatelessNode {
                        StatelessNode(subtitle: self.subtitle, model: self.model, content: self.content, footer: {
                                self.footer
                            })
                    }
                }
                """,
            macros: macros
        )
    }

    func testViewConformanceIsDetectedAndDelegatingBodyIsGenerated() {
        assertMacroExpansion(
            """
            @StatelessNode
            struct Card: View {
                let title: String
            }
            """,
            expandedSource: """
                struct Card: View {
                    let title: String

                    /// Conforms to `View`, declared by `@StatelessNode` — implement its real
                    /// `body` in a separate extension, e.g. `extension YourType.StatelessNode {
                    /// public var body: some View { ... } }`.
                    @DataLayout
                    struct StatelessNode: View {
                        let title: String
                    }

                    var statelessNode: StatelessNode {
                        StatelessNode(title: self.title)
                    }

                    var body: some View {
                        self.statelessNode
                    }
                }
                """,
            macros: macros
        )
    }

    func testViewModifierConformanceIsDetectedAndDelegatingBodyIsGenerated() {
        assertMacroExpansion(
            """
            @StatelessNode
            struct VM: ViewModifier {
                @State private var c: Int = 0
            }
            """,
            expandedSource: """
                struct VM: ViewModifier {
                    @State private var c: Int = 0

                    /// Conforms to `ViewModifier`, declared by `@StatelessNode` — implement its
                    /// real `body(content:)` in a separate extension, e.g. `extension
                    /// YourType.StatelessNode { public func body(content: Content) -> some View
                    /// { ... } }`.
                    @DataLayout
                    struct StatelessNode: ViewModifier {
                        @Binding var c: Int
                    }

                    var statelessNode: StatelessNode {
                        StatelessNode(c: self.$c)
                    }

                    func body(content: Content) -> some View {
                        content.modifier(self.statelessNode)
                    }
                }
                """,
            macros: macros
        )
    }

    func testConformanceDeclaredInASeparateExtensionIsNotDetected() {
        // Syntax-only detection reads the attached declaration's own inheritance
        // clause — conformance added elsewhere (a separate `extension Card: View`)
        // is invisible to it, since macros never get a type checker. Documented
        // limitation, not a bug: no `body` member, no `: View` on StatelessNode.
        assertMacroExpansion(
            """
            @StatelessNode
            struct Card {
                let title: String
            }
            """,
            expandedSource: """
                struct Card {
                    let title: String

                    @DataLayout
                    struct StatelessNode {
                        let title: String
                    }

                    var statelessNode: StatelessNode {
                        StatelessNode(title: self.title)
                    }
                }
                """,
            macros: macros
        )
    }

    func testAccessLevelMirrorsTheStruct() {
        assertMacroExpansion(
            """
            @StatelessNode
            public struct Point {
                var x: Int
                var y: Int
            }
            """,
            expandedSource: """
                public struct Point {
                    var x: Int
                    var y: Int

                    @DataLayout
                    public struct StatelessNode {
                        public var x: Int
                        public var y: Int
                    }

                    public var statelessNode: StatelessNode {
                        StatelessNode(x: self.x, y: self.y)
                    }
                }
                """,
            macros: macros
        )
    }
}
