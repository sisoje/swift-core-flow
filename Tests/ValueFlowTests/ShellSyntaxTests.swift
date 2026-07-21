import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import ValueFlowMacros

final class ShellSyntaxTests: XCTestCase {
    let macros: [String: Macro.Type] = ["Shell": ShellMacro.self]

    func testMixOfPlainQueryEnvironmentStateAndBindingFields() {
        assertMacroExpansion(
            """
            @Shell
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

                    struct Core {
                        @QueryCore var items: [Item]
                        let colorScheme: ColorScheme
                        @Binding var isExpanded: Bool
                        @Binding var isOn: Bool
                        let title: String
                    }

                    var core: Core {
                        Core(items: QueryCore(wrappedValue: _items.wrappedValue, fetchError: _items.fetchError, modelContext: _items.modelContext), colorScheme: colorScheme, isExpanded: $isExpanded, isOn: $isOn, title: title)
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
        // @propertyWrapper-attributed, so it redeclares onto Core the
        // same way @Binding does for @State/@AppStorage.
        assertMacroExpansion(
            """
            @Shell
            struct SearchField {
                @FocusState private var isFocused: Bool
                let title: String
            }
            """,
            expandedSource: """
                struct SearchField {
                    @FocusState private var isFocused: Bool
                    let title: String

                    struct Core {
                        @FocusState<Bool>.Binding var isFocused: Bool
                        let title: String
                    }

                    var core: Core {
                        Core(isFocused: $isFocused, title: title)
                    }
                }
                """,
            macros: macros
        )
    }

    func testGestureStateRedeclaresAsGestureStateCoreWrappingTheLiveInstance() {
        // @GestureStateCore wraps the captured live GestureState instance and
        // forwards wrappedValue/projectedValue to it — so `core.dragOffset`
        // reads the mid-gesture value and `.updating($dragOffset)` in Core's
        // body wires the real gesture, byte-identical to the live property.
        assertMacroExpansion(
            """
            @Shell
            struct Draggable {
                @GestureState private var dragOffset: CGSize = .zero
                let title: String
            }
            """,
            expandedSource: """
                struct Draggable {
                    @GestureState private var dragOffset: CGSize = .zero
                    let title: String

                    struct Core {
                        @GestureStateCore var dragOffset: CGSize
                        let title: String
                    }

                    var core: Core {
                        Core(dragOffset: GestureStateCore(_dragOffset), title: title)
                    }
                }
                """,
            macros: macros
        )
    }

    func testAccessibilityFocusStateGetsFocusStatesExactTreatment() {
        // An exact @FocusState clone — verified directly against the real
        // SwiftUI interface: same nested @propertyWrapper Binding shape,
        // settable wrappedValue, no conversion to Binding<T> — so it gets the
        // same substituted-attribute treatment, and snap.$x feeds
        // .accessibilityFocused(_:) directly.
        assertMacroExpansion(
            """
            @Shell
            struct SearchField {
                @AccessibilityFocusState private var a11yFocused: Bool
                let title: String
            }
            """,
            expandedSource: """
                struct SearchField {
                    @AccessibilityFocusState private var a11yFocused: Bool
                    let title: String

                    struct Core {
                        @AccessibilityFocusState<Bool>.Binding var a11yFocused: Bool
                        let title: String
                    }

                    var core: Core {
                        Core(a11yFocused: $a11yFocused, title: title)
                    }
                }
                """,
            macros: macros
        )
    }

    func testScaledMetricIsCapturedAsAPlainLetLikeEnvironment() {
        // Get-only wrappedValue, no projectedValue at all (verified directly)
        // — a one-time capture of the current scaled value. Redeclaring
        // @ScaledMetric on Core would double-scale: its init takes the *base*
        // value, but the host reads back the already-scaled one.
        assertMacroExpansion(
            """
            @Shell
            struct IconRow {
                @ScaledMetric private var iconSize: CGFloat = 24
                let title: String
            }
            """,
            expandedSource: """
                struct IconRow {
                    @ScaledMetric private var iconSize: CGFloat = 24
                    let title: String

                    struct Core {
                        let iconSize: CGFloat
                        let title: String
                    }

                    var core: Core {
                        Core(iconSize: iconSize, title: title)
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
            @Shell
            struct SearchField {
                @SceneStorage("isPinned") private var isPinned: Bool = false
                let title: String
            }
            """,
            expandedSource: """
                struct SearchField {
                    @SceneStorage("isPinned") private var isPinned: Bool = false
                    let title: String

                    struct Core {
                        @Binding var isPinned: Bool
                        let title: String
                    }

                    var core: Core {
                        Core(isPinned: $isPinned, title: title)
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
            @Shell
            struct HeroCard {
                @Namespace private var ns
                let title: String
            }
            """,
            expandedSource: """
                struct HeroCard {
                    @Namespace private var ns
                    let title: String

                    struct Core {
                        let ns: Namespace.ID
                        let title: String
                    }

                    var core: Core {
                        Core(ns: ns, title: title)
                    }
                }
                """,
            macros: macros
        )
    }

    func testZeroEligibleFieldsStillGeneratesAnEmptyCoreStruct() {
        // No plain private fallthrough field here — a private property with no
        // recognized wrapper is a compile error now (see
        // testDiagnosesPlainPrivatePropertyWithNoWrapper), so zero eligible fields
        // means zero stored properties at all.
        assertMacroExpansion(
            """
            @Shell
            struct Empty {}
            """,
            expandedSource: """
                struct Empty {

                    struct Core {

                    }

                    var core: Core {
                        Core()
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
            @Shell
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

                    struct Core {
                        let subtitle: String?
                        @Bindable var model: Settings
                        @ViewBuilder let content: () -> Content
                        let footer: Content
                    }

                    var core: Core {
                        Core(subtitle: subtitle, model: model, content: content, footer: footer)
                    }
                }
                """,
            macros: macros
        )
    }

    func testViewConformanceIsDetectedAndDelegatingBodyIsGenerated() {
        assertMacroExpansion(
            """
            @Shell
            struct Card: View {
                let title: String
            }
            """,
            expandedSource: """
                struct Card: View {
                    let title: String

                    /// Conforms to `View`, declared by `@Shell` — implement its real
                    /// `body` in a separate extension, e.g. `extension YourType.Core {
                    /// var body: some View { ... } }`.
                    struct Core: View {
                        let title: String
                    }

                    var core: Core {
                        Core(title: title)
                    }

                    var body: some View {
                        core
                    }
                }
                """,
            macros: macros
        )
    }

    func testViewModifierConformanceIsDetectedAndDelegatingBodyIsGenerated() {
        assertMacroExpansion(
            """
            @Shell
            struct VM: ViewModifier {
                @State private var c: Int = 0
            }
            """,
            expandedSource: """
                struct VM: ViewModifier {
                    @State private var c: Int = 0

                    /// Conforms to `ViewModifier`, declared by `@Shell` — implement its
                    /// real `body(content:)` in a separate extension, e.g. `extension
                    /// YourType.Core { func body(content: Content) -> some View
                    /// { ... } }`.
                    struct Core: ViewModifier {
                        @Binding var c: Int
                    }

                    var core: Core {
                        Core(c: $c)
                    }

                    func body(content: Content) -> some View {
                        content.modifier(core)
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
        // limitation, not a bug: no `body` member, no `: View` on Core.
        assertMacroExpansion(
            """
            @Shell
            struct Card {
                let title: String
            }
            """,
            expandedSource: """
                struct Card {
                    let title: String

                    struct Core {
                        let title: String
                    }

                    var core: Core {
                        Core(title: title)
                    }
                }
                """,
            macros: macros
        )
    }

    func testPublicViewHostStillGetsAPublicBodyDelegatingToAnInternalCore() {
        // `body`'s own access still mirrors the host (public), verified directly
        // that this compiles even though it returns `core`, an
        // internal concrete type — `some View`'s opaque return type only exposes
        // the `View` conformance, never the concrete type, so a public `body` can
        // freely return an internal value.
        assertMacroExpansion(
            """
            @Shell
            public struct Card: View {
                let title: String
            }
            """,
            expandedSource: """
                public struct Card: View {
                    let title: String

                    /// Conforms to `View`, declared by `@Shell` — implement its real
                    /// `body` in a separate extension, e.g. `extension YourType.Core {
                    /// var body: some View { ... } }`.
                    struct Core: View {
                        let title: String
                    }

                    var core: Core {
                        Core(title: title)
                    }

                    public var body: some View {
                        core
                    }
                }
                """,
            macros: macros
        )
    }

    func testCoreIsAlwaysInternalRegardlessOfTheStructsAccess() {
        assertMacroExpansion(
            """
            @Shell
            public struct Point {
                var x: Int
                var y: Int
            }
            """,
            expandedSource: """
                public struct Point {
                    var x: Int
                    var y: Int

                    struct Core {
                        let x: Int
                        let y: Int
                    }

                    var core: Core {
                        Core(x: x, y: y)
                    }
                }
                """,
            macros: macros
        )
    }
}
