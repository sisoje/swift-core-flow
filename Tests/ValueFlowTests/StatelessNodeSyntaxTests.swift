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

                    struct StatelessNode {
                        let items: (result: [Item], fetchError: Error?, modelContext: ModelContext)
                        let colorScheme: ColorScheme
                        @Binding var isExpanded: Bool
                        @Binding var isOn: Bool
                        let title: String
                    }

                    var statelessNode: StatelessNode {
                        StatelessNode(items: (result: items, fetchError: _items.fetchError, modelContext: _items.modelContext), colorScheme: colorScheme, isExpanded: $isExpanded, isOn: _isOn, title: title)
                    }
                }
                """,
            macros: macros
        )
    }

    func testFocusStateRedeclaresItsOwnRealBindingAttributeNotAt() {
        // @FocusState gets its own substituted attribute — @FocusState<T>.Binding,
        // not @Binding — since @FocusState's own projectedValue is
        // FocusState<T>.Binding, not Binding<T> (verified directly, no public
        // conversion between the two). The real FocusState<T>.Binding is itself
        // @propertyWrapper-attributed, so it redeclares onto StatelessNode the
        // same way @Binding does for @State/@AppStorage.
        assertMacroExpansion(
            """
            @StatelessNode
            struct SearchField {
                @FocusState private var isFocused: Bool
                let title: String
            }
            """,
            expandedSource: """
                struct SearchField {
                    @FocusState private var isFocused: Bool
                    let title: String

                    struct StatelessNode {
                        @FocusState<Bool>.Binding var isFocused: Bool
                        let title: String
                    }

                    var statelessNode: StatelessNode {
                        StatelessNode(isFocused: $isFocused, title: title)
                    }
                }
                """,
            macros: macros
        )
    }

    func testSceneStorageFoldsIntoTheSameBindingSubstitutionAsAppStorage() {
        // @SceneStorage shares @State/@AppStorage's exact shape (settable
        // wrappedValue, projectedValue genuinely Binding<T> — verified directly
        // against the real SwiftUI interface), so it gets the same @Binding var
        // substitution, no separate case needed unlike @FocusState.
        assertMacroExpansion(
            """
            @StatelessNode
            struct SearchField {
                @SceneStorage("isPinned") private var isPinned: Bool = false
                let title: String
            }
            """,
            expandedSource: """
                struct SearchField {
                    @SceneStorage("isPinned") private var isPinned: Bool = false
                    let title: String

                    struct StatelessNode {
                        @Binding var isPinned: Bool
                        let title: String
                    }

                    var statelessNode: StatelessNode {
                        StatelessNode(isPinned: $isPinned, title: title)
                    }
                }
                """,
            macros: macros
        )
    }

    func testNamespaceIsGroupedWithEnvironmentAsAPlainLetAndNeedsNoExplicitType() {
        // @Namespace has no projectedValue at all (unlike @State/@AppStorage/
        // @FocusState) and a get-only wrappedValue (like @Environment) —
        // verified directly against the real SwiftUI interface — so it gets
        // the exact same plain, unattributed `let` treatment @Environment does,
        // read via a bare `x`. Unlike every other recognized wrapper,
        // `@Namespace` needs no explicit type annotation at all: it has exactly
        // one possible wrapped type (`Namespace.ID`), so this macro fills that
        // in itself rather than diagnosing a missing type.
        assertMacroExpansion(
            """
            @StatelessNode
            struct HeroCard {
                @Namespace private var ns
                let title: String
            }
            """,
            expandedSource: """
                struct HeroCard {
                    @Namespace private var ns
                    let title: String

                    struct StatelessNode {
                        let ns: Namespace.ID
                        let title: String
                    }

                    var statelessNode: StatelessNode {
                        StatelessNode(ns: ns, title: title)
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

    func testPlainAndViewBuilderFieldsAreLetWhileBindableStaysVar() {
        // @ViewBuilder is mirrored only for the stored-closure form (content) —
        // its field type is already a closure, so the attribute is pure upside.
        // For the stored-value form (footer), mirroring it would force Swift's
        // synthesized init to wrap the parameter in a builder closure purely to
        // satisfy the attribute (verified directly) — dropped entirely instead,
        // so footer stays a plain `let footer: Content`, passed straight
        // through with no wrapping on either side.
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

                    struct StatelessNode {
                        let subtitle: String?
                        @Bindable var model: Settings
                        @ViewBuilder let content: () -> Content
                        let footer: Content
                    }

                    var statelessNode: StatelessNode {
                        StatelessNode(subtitle: subtitle, model: model, content: content, footer: footer)
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
                    /// var body: some View { ... } }`.
                    struct StatelessNode: View {
                        let title: String
                    }

                    var statelessNode: StatelessNode {
                        StatelessNode(title: title)
                    }

                    var body: some View {
                        statelessNode
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
                    /// YourType.StatelessNode { func body(content: Content) -> some View
                    /// { ... } }`.
                    struct StatelessNode: ViewModifier {
                        @Binding var c: Int
                    }

                    var statelessNode: StatelessNode {
                        StatelessNode(c: $c)
                    }

                    func body(content: Content) -> some View {
                        content.modifier(statelessNode)
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

                    struct StatelessNode {
                        let title: String
                    }

                    var statelessNode: StatelessNode {
                        StatelessNode(title: title)
                    }
                }
                """,
            macros: macros
        )
    }

    func testPublicViewHostStillGetsAPublicBodyDelegatingToAnInternalStatelessNode() {
        // `body`'s own access still mirrors the host (public), verified directly
        // that this compiles even though it returns `statelessNode`, an
        // internal concrete type — `some View`'s opaque return type only exposes
        // the `View` conformance, never the concrete type, so a public `body` can
        // freely return an internal value.
        assertMacroExpansion(
            """
            @StatelessNode
            public struct Card: View {
                let title: String
            }
            """,
            expandedSource: """
                public struct Card: View {
                    let title: String

                    /// Conforms to `View`, declared by `@StatelessNode` — implement its real
                    /// `body` in a separate extension, e.g. `extension YourType.StatelessNode {
                    /// var body: some View { ... } }`.
                    struct StatelessNode: View {
                        let title: String
                    }

                    var statelessNode: StatelessNode {
                        StatelessNode(title: title)
                    }

                    public var body: some View {
                        statelessNode
                    }
                }
                """,
            macros: macros
        )
    }

    func testStatelessNodeIsAlwaysInternalRegardlessOfTheStructsAccess() {
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

                    struct StatelessNode {
                        let x: Int
                        let y: Int
                    }

                    var statelessNode: StatelessNode {
                        StatelessNode(x: x, y: y)
                    }
                }
                """,
            macros: macros
        )
    }
}
