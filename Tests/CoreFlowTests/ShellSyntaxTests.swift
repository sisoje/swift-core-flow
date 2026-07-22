import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import CoreFlowMacros

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
                        @RawProperty @QueryCore var items: [Item]
                        var colorScheme: ColorScheme
                        @RawProperty @Binding var isExpanded: Bool
                        @RawProperty @Binding var isOn: Bool
                        var title: String
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
                        @RawProperty @FocusState<Bool>.Binding var isFocused: Bool
                        var title: String
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
        // @GestureStateCore wraps a live GestureState instance whole and
        // forwards wrappedValue/projectedValue to it — so `dragOffset` reads
        // the mid-gesture value, `.updating($dragOffset)` in the copied body
        // takes the real GestureState<T>, and every argument-carrying init
        // (reset:/resetTransaction:/initialValue: spellings) carries over for
        // free, since the reset behavior lives inside the instance. An earlier
        // design mirrored a fresh `@GestureState var` instead — it silently
        // swapped a custom reset for the default one, proved live by
        // TrickyDragCardUITests in the ExampleApp.
        assertMacroExpansion(
            """
            @Shell
            struct Draggable {
                @GestureState(reset: { _, transaction in transaction = Transaction() }) private var dragOffset: CGSize = .zero
                let title: String
            }
            """,
            expandedSource: """
                struct Draggable {
                    @GestureState(reset: { _, transaction in transaction = Transaction() }) private var dragOffset: CGSize = .zero
                    let title: String

                    struct Core {
                        @RawProperty @GestureStateCore var dragOffset: CGSize
                        var title: String
                    }

                    var core: Core {
                        Core(dragOffset: GestureStateCore($dragOffset), title: title)
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
                        @RawProperty @AccessibilityFocusState<Bool>.Binding var a11yFocused: Bool
                        var title: String
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
        // — a plain value field. Redeclaring @ScaledMetric on Core would
        // double-scale: its init takes the *base* value, but the host reads
        // back the already-scaled one.
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
                        var iconSize: CGFloat
                        var title: String
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
                        @RawProperty @Binding var isPinned: Bool
                        var title: String
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
        // the exact same plain, unattributed `let` treatment @Environment does.
        // Unlike every other recognized wrapper, `@Namespace` needs no explicit
        // type annotation at all: it has exactly one possible wrapped type
        // (`Namespace.ID`), so this macro fills that in itself rather than
        // diagnosing a missing type.
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
                        var ns: Namespace.ID
                        var title: String
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
                        var subtitle: String?
                        @RawProperty @Bindable var model: Settings
                        @ViewBuilder var content: () -> Content
                        var footer: Content
                    }

                    var core: Core {
                        Core(subtitle: subtitle, model: model, content: content, footer: footer)
                    }
                }
                """,
            macros: macros
        )
    }

    func testBodyIsCopiedIntoCoreVerbatim() {
        // The host writes a completely normal SwiftUI body; @Shell copies it
        // verbatim into Core (same expansion — referencing its own generated
        // fields is legal; only cross-expansion references are forbidden), and
        // Core's `: View` conformance is satisfied by the copy. One source
        // text serves both types: the identifiers resolve against the host's
        // real wrappers on one side and Core's substituted fields on the
        // other, by the one-to-one read-surface design.
        assertMacroExpansion(
            """
            @Shell
            struct Card: View {
                @State private var count: Int = 0
                var body: some View {
                    Text("\\(count)")
                }
            }
            """,
            expandedSource: """
                struct Card: View {
                    @State private var count: Int = 0
                    var body: some View {
                        Text("\\(count)")
                    }

                    struct Core: View {
                        @RawProperty @Binding var count: Int

                        var body: some View {
                            Text("\\(count)")
                        }
                    }

                    var core: Core {
                        Core(count: $count)
                    }
                }
                """,
            macros: macros
        )
    }

    func testBodyContentIsCopiedIntoCoreForViewModifierHosts() {
        // Same copy for the ViewModifier shape: `Content` inside the copied
        // body(content:) resolves to Core's own ViewModifier.Content — a
        // different concrete type from the host's (each is keyed on its own
        // conforming type — verified directly), which is fine: each type
        // satisfies the protocol independently.
        assertMacroExpansion(
            """
            @Shell
            struct Dimmed: ViewModifier {
                @State private var level: Double = 0.5
                func body(content: Content) -> some View {
                    content.opacity(level)
                }
            }
            """,
            expandedSource: """
                struct Dimmed: ViewModifier {
                    @State private var level: Double = 0.5
                    func body(content: Content) -> some View {
                        content.opacity(level)
                    }

                    struct Core: ViewModifier {
                        @RawProperty @Binding var level: Double

                        func body(content: Content) -> some View {
                            content.opacity(level)
                        }
                    }

                    var core: Core {
                        Core(level: $level)
                    }
                }
                """,
            macros: macros
        )
    }

    func testHelpersStaticMembersAndNestedTypesAreCopiedButInitsAreNot() {
        // Every non-stored member rides along into Core — helper computed
        // properties, methods, static members (static stored included: a body
        // referencing `spacing` unqualified needs Core to carry its own copy),
        // nested types — so the copied body's helpers resolve without a
        // separate extension. Initializers are the one exception: Core is
        // constructed through Swift's synthesized memberwise init (in tests,
        // with mocks), and a copied init would suppress that synthesis.
        assertMacroExpansion(
            """
            @Shell
            struct Card: View {
                @State private var count: Int = 0
                static let spacing: CGFloat = 8
                enum Kind {
                    case a
                }
                init(seed: Int) {
                    count = seed
                }
                var doubled: Int {
                    count * 2
                }
                func label() -> String {
                    "\\(doubled)"
                }
                var body: some View {
                    Text(label())
                }
            }
            """,
            expandedSource: """
                struct Card: View {
                    @State private var count: Int = 0
                    static let spacing: CGFloat = 8
                    enum Kind {
                        case a
                    }
                    init(seed: Int) {
                        count = seed
                    }
                    var doubled: Int {
                        count * 2
                    }
                    func label() -> String {
                        "\\(doubled)"
                    }
                    var body: some View {
                        Text(label())
                    }

                    struct Core: View {
                        @RawProperty @Binding var count: Int

                        static let spacing: CGFloat = 8

                        enum Kind {
                            case a
                        }

                        var doubled: Int {
                            count * 2
                        }

                        func label() -> String {
                            "\\(doubled)"
                        }

                        var body: some View {
                            Text(label())
                        }
                    }

                    var core: Core {
                        Core(count: $count)
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
        // limitation, not a bug: no `: View` on Core.
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
                        var title: String
                    }

                    var core: Core {
                        Core(title: title)
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
                        var x: Int
                        var y: Int
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
