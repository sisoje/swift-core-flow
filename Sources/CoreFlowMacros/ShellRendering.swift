import SwiftSyntax

/// `Core` — the host's standalone twin: every collected stored property
/// (collection already refused anything unrenderable —
/// `plainPrivatePropertyNotAllowed`, `StoredProperty.swift`) plus a verbatim
/// copy of every non-stored member. Three field rules, each documented at
/// its branch below.
///
/// `Core` and every mapped field are always internal, regardless of the
/// host's access (verbatim copies keep their own access, `public` erased):
/// a testing/preview seam, not API surface. No init is generated or
/// copied — a copied init would suppress the synthesized memberwise init,
/// the only way tests construct a `Core`, and synthesis already reproduces
/// every field-specific behavior (verified directly: a wrapper without
/// `init(wrappedValue:)` (`@Binding`) synthesizes a parameter of the
/// *wrapper's* type, one with it (`@QueryCore`, `@Bindable`) of the
/// *wrapped* type, `@ViewBuilder` on a stored `let` a real builder
/// parameter). Deliberately no `core` capture property off the live host —
/// a unit test never has one — and no generated binding mocks: that small,
/// situational code belongs at the use site, shaped by the test (see
/// `ShellTests`).
func renderShell(
    properties: [StoredProperty], hostKind: ShellHostKind = .none,
    copiedMembers: [String] = []
) -> [DeclSyntax] {
    let fieldDecls = properties.map { p -> String in
        // Rule 2 — the whitelist (`isSubstitutedOnCore`): the source-of-truth
        // set becomes test-suppliable stand-ins. @State/@AppStorage/
        // @SceneStorage share one case — each one's projectedValue genuinely
        // IS Binding<T> (verified directly), so a test-supplied
        // Binding(get:set:) captures every write the copied body makes.
        // @Query → @QueryCore, whose extra fields default so the memberwise
        // init takes the bare fetched value: `Core(items: [item], …)`.
        // @FocusState/@AccessibilityFocusState are deliberately NOT here:
        // their .Binding projections have no public initializer and their
        // writes no-op outside a live view (both verified directly) — a
        // substitution would be a pass-through, not a mock.
        if p.isBindingBackedStorage {
            return "@Binding var \(p.name): \(p.type?.trimmedDescription ?? "")"
        }
        if p.isQuery {
            return "@QueryCore var \(p.name): \(p.type?.trimmedDescription ?? "")"
        }
        // @ViewBuilder isn't a property wrapper: the stored-closure form
        // keeps the attribute (real builder syntax at Core's init call
        // site), the stored-value form drops it — keeping it would make the
        // synthesized init wrap the parameter in a builder closure to no
        // benefit (verified directly).
        if p.isViewBuilder {
            let type = p.type?.trimmedDescription ?? ""
            let isStoredValue = !(p.type.map(isFunctionType) ?? false)
            return isStoredValue
                ? "var \(p.name): \(type)"
                : "@ViewBuilder var \(p.name): \(type)"
        }
        // Rule 1 — plain let/var: specifier and default kept, access
        // stripped. Swift's memberwise rules then apply as on the host: a
        // `let` with a default is a constant, no init parameter.
        guard let attributeText = p.attributeText else {
            let def = p.defaultValue.map { " = \($0.trimmedDescription)" } ?? ""
            let spec = p.isLet ? "let" : "var"
            return "\(spec) \(p.name): \(p.type?.trimmedDescription ?? "")\(def)"
        }
        // Rule 3 — ANY other wrapper (@Binding included — its verbatim copy
        // already IS the mock vehicle): whole declaration copied — attribute
        // arguments, default, `private` kept, `public` erased. Argument
        // behavior rides along byte-for-byte — proved live by
        // TrickyDragCardUITests: its custom @GestureState(reset:) closure
        // fires on Core's copy exactly as on the host; rebuilding from the
        // bare wrapper name would swap it for the default. A private copy is
        // self-initializing by construction, so it drops out of the
        // memberwise init (verified for @Environment arguments, @GestureState
        // inline default, and @Namespace wrapper init()) — sealed: an
        // @Environment copy reads the real environment when hosted (mock via
        // .environment(...)) and default EnvironmentValues outside;
        // @GestureState starts a fresh gesture at its declared default. A
        // non-private copy stays a memberwise parameter of the wrapper's
        // own type.
        let access = p.isPrivate ? "private " : ""
        let type = p.type.map { ": \($0.trimmedDescription)" } ?? ""
        let def = p.defaultValue.map { " = \($0.trimmedDescription)" } ?? ""
        return "\(attributeText) \(access)var \(p.name)\(type)\(def)"
    }.joined(separator: "\n")

    let conformance: String
    switch hostKind {
    case .view: conformance = ": View"
    case .viewModifier: conformance = ": ViewModifier"
    case .none: conformance = ""
    }

    let copies = copiedMembers.map { "\n\n\($0)" }.joined()
    let statelessStruct = DeclSyntax(
        stringLiteral: """
            struct Core\(conformance) {
            \(fieldDecls)\(copies)
            }
            """
    )

    return [statelessStruct]
}
