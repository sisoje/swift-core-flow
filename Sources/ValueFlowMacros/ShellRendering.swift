import SwiftSyntax

/// Renders `@Shell`'s two generated members — a nested `Core` struct plus a
/// `core` computed property capturing one off the live instance — over
/// exactly `OutFlow`'s field set (`outFlowProperties`, reused directly — see
/// its doc comment in `FlowableRendering.swift`), each source-of-truth
/// wrapper substituted with a plain, mockable stand-in, followed by a
/// verbatim copy of every non-stored host member (`copiedMembers` — computed
/// by `copiedMemberSources` in `ShellMacro.swift`, `body` included). The host
/// stays a completely ordinary SwiftUI view; `Core` is its standalone twin,
/// constructed directly in tests/previews via Swift's own synthesized
/// memberwise init — which is also why `@Shell` copies no initializers: a
/// copied init would suppress that synthesis.
///
/// `Core` is always internal — the struct itself and every field —
/// regardless of the attached type's own access level, and it carries no
/// `@Flowable`. It's a testing/preview seam, not API surface: consumers of a
/// public host never need the twin, only the module's own tests do. Swift's
/// memberwise-init synthesis reproduces every field-specific behavior a
/// hand-rolled init would — verified directly: a property-wrapper field with
/// no `init(wrappedValue:)` (`@Binding`) synthesizes a parameter of the
/// *wrapper's* type, one that does (`@Bindable`) synthesizes a parameter of
/// the *wrapped* type, and `@ViewBuilder` directly on a stored `let`
/// synthesizes a real builder parameter.
///
/// Every private wrapper kind becomes a *plain, constructed* field on
/// `Core` — never the original attribute, always a mockable value:
/// - `@Query` → `@QueryCore var name: T` — this package's own drop-in stand-in
///   (see `QueryCore.swift`), carrying the live wrapper's exact instance
///   surface: `wrappedValue`, `fetchError`, `modelContext`, no
///   `projectedValue`.
/// - `@GestureState` → `@GestureStateCore var name: T` — wraps a
///   `GestureState<T>` instance whole: `name` reads the mid-gesture value,
///   `$name` hands `.updating(_:)` the real `GestureState<T>`, and — the
///   reason this beats mirroring a fresh `@GestureState var` (an earlier
///   design, reverted) — every argument-carrying init the host used
///   (`reset:`/`resetTransaction:`/`initialValue:` spellings) carries over
///   for free, since the reset behavior lives inside the instance. Proved
///   live by TrickyDragCardUITests in the ExampleApp: the mirror design
///   silently swapped a custom reset for the default one; the instance
///   capture fires it.
/// - `@State`/`@AppStorage`/`@SceneStorage` → `@Binding var name: T` (their own
///   storage only installs inside a live SwiftUI view and can't be redeclared
///   on a plain struct; all three share this case because each one's
///   `projectedValue` genuinely *is* `Binding<T>` — verified directly against
///   the real SwiftUI interface, `wrappedValue` is `{ get nonmutating set }`
///   for each).
/// - `@FocusState` → `@FocusState<T>.Binding var name: T`, its own substituted
///   attribute, distinct from `@Binding` above. `@FocusState`'s own
///   `projectedValue` is `FocusState<T>.Binding`, **not** `Binding<T>` — verified
///   directly against the real SwiftUI interface: it exposes only
///   `wrappedValue` and `projectedValue` (itself), no conversion to `Binding<T>`
///   and no public initializer either. The real `FocusState<T>.Binding` is
///   itself `@propertyWrapper`-attributed (verified directly), so it
///   redeclares onto `Core` the same way `@Binding` does — `snap.name` reads
///   the value, `snap.$name` feeds `.focused(_:)` directly.
/// - `@AccessibilityFocusState` → an exact `@FocusState` clone (verified
///   directly — same nested `@propertyWrapper` `Binding` shape), so the same
///   substitution.
/// - `@Environment`/`@Namespace`/`@ScaledMetric` → a plain `var name: T` — no
///   attribute at all. Get-only `wrappedValue`, no `projectedValue` to
///   substitute (verified directly for each), so a plain unattributed field
///   is the only option. For `@ScaledMetric` specifically, redeclaring it
///   would double-scale: its init takes the *base* value, but the host reads
///   back the already-scaled one.
///
/// Every other field mirrors the *original* property's own attribute (if any)
/// and declared type onto `Core` verbatim. Every field is `var`, regardless
/// of the original's `let`/`var`, and every genuine-wrapper field is stamped
/// `@RawProperty` — a captured copy is meant to be re-mocked field by field,
/// wrapper instances included; `let core = shell.core` still freezes the
/// whole value, since immutability belongs to the binding, not the type.
/// `@ViewBuilder` (a result-builder attribute, not a wrapper — legal on
/// stored properties, verified directly) is mirrored only for the
/// stored-*closure* form, where it buys real builder syntax at the init call
/// site; for the stored-*value* form it would make the synthesized init wrap
/// the parameter in a builder closure purely to satisfy the attribute
/// (verified directly), so it's dropped there.
func renderShell(
    properties: [StoredProperty], access: String, hostKind: ShellHostKind = .none,
    copiedMembers: [String] = []
) -> [DeclSyntax] {
    // Core's field set is identical to OutFlow's — reused directly rather
    // than duplicating the filter.
    let fields = outFlowProperties(properties)

    // Every field is internal — never `access` — regardless of the attached
    // type's own access level; see this file's own doc comment.
    //
    // Every field is `var`, and every genuine-wrapper field is additionally
    // stamped @RawProperty (this package's own peer macro, expanded by the
    // compiler inside this very expansion — its raw_ accessor exposes the
    // wrapper's private _name backing storage). Together they make a captured
    // copy fully re-mockable: `var m = shell.core; m.raw_isOn = .constant(false)`.
    let fieldDecls = fields.map { p -> String in
        if p.isBindingBackedStorage || p.isBinding {
            return "@RawProperty @Binding var \(p.name): \(p.type?.trimmedDescription ?? "")"
        }
        if p.isFocusState {
            let type = p.type?.trimmedDescription ?? ""
            return "@RawProperty @FocusState<\(type)>.Binding var \(p.name): \(type)"
        }
        if p.isAccessibilityFocusState {
            let type = p.type?.trimmedDescription ?? ""
            return "@RawProperty @AccessibilityFocusState<\(type)>.Binding var \(p.name): \(type)"
        }
        if p.isEnvironment || p.isNamespace || p.isScaledMetric {
            return "var \(p.name): \(p.type?.trimmedDescription ?? "")"
        }
        if p.isQuery {
            return "@RawProperty @QueryCore var \(p.name): \(p.type?.trimmedDescription ?? "")"
        }
        if p.isGestureState {
            return
                "@RawProperty @GestureStateCore var \(p.name): \(p.type?.trimmedDescription ?? "")"
        }
        // @ViewBuilder isn't a property wrapper (no backing storage), so no
        // @RawProperty; any other attribute here is a genuine mirrored wrapper
        // (@Bindable, …) and gets one.
        let isStoredValueViewBuilder = p.isViewBuilder && !(p.type.map(isFunctionType) ?? false)
        let attributePrefix =
            isStoredValueViewBuilder ? "" : p.wrapperName.map { "@\($0) " } ?? ""
        let rawPrefix = p.wrapperName != nil && !p.isViewBuilder ? "@RawProperty " : ""
        return "\(rawPrefix)\(attributePrefix)var \(p.name): \(outFlowFieldType(p))"
    }.joined(separator: "\n")

    let conformance: String
    switch hostKind {
    case .view: conformance = ": View"
    case .viewModifier: conformance = ": ViewModifier"
    case .none: conformance = ""
    }

    // The host's non-stored members, copied verbatim — legal because this is
    // the same expansion that declares Core's fields, and the identifiers
    // inside resolve against them by the one-to-one read-surface design (see
    // this function's doc comment).
    let copies = copiedMembers.map { "\n\n\($0)" }.joined()
    let statelessStruct = DeclSyntax(
        stringLiteral: """
            struct Core\(conformance) {
            \(fieldDecls)\(copies)
            }
            """
    )

    // Captures a Core off the live host instance: every field reads the way
    // `outFlow` does (`outFlowFieldReadExpression`) and is passed straight
    // through. Always internal, like Core itself.
    let args = fields.map { p -> String in
        "\(p.name): \(outFlowFieldReadExpression(p))"
    }.joined(separator: ", ")
    let statelessProperty = DeclSyntax(
        stringLiteral: """
            var core: Core {
                Core(\(args))
            }
            """
    )
    return [statelessStruct, statelessProperty]
}
