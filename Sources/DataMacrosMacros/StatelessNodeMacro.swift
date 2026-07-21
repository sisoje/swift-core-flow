import SwiftSyntax
import SwiftSyntaxMacros

/// Which of SwiftUI's two `body`-shaped protocols the attached type declares
/// conformance to, detected syntactically off its own inheritance clause (see
/// `detectHostKind`) — not a real semantic conformance check (macros never get
/// one; see `detectHostKind`'s own doc comment for exactly what that misses).
enum StatelessNodeHostKind {
    case view
    case viewModifier
    case none
}

/// Reads `declaration`'s own inheritance clause — the `: View`/`: ViewModifier`
/// written directly on the type — for a bare `View`/`ViewModifier` identifier,
/// the same textual, syntax-only style `propertyWrapperName` (`StoredProperty.swift`)
/// already uses for property-wrapper attributes.
///
/// **This is textual, not semantic — it cannot be, since macros never get a type
/// checker (verified directly against the pinned swift-syntax dependency itself:
/// `MemberMacro.expansion` receives only `some DeclGroupSyntax` +
/// `some MacroExpansionContext`, no semantic model, on the `603.0.2` this package
/// resolves to within its `600.0.0..<700.0.0` range).** Concretely, this misses:
/// conformance declared in a *separate* extension elsewhere in the file/module,
/// conformance via a typealias or protocol composition, and qualified spellings
/// (`SwiftUI.View`) — only a bare `View`/`ViewModifier` identifier directly in the
/// attached declaration's own inheritance clause is recognized.
func detectHostKind(of declaration: some DeclGroupSyntax) -> StatelessNodeHostKind {
    let inherited =
        declaration.inheritanceClause?.inheritedTypes.compactMap {
            $0.type.as(IdentifierTypeSyntax.self)?.name.text
        } ?? []
    if inherited.contains("ViewModifier") { return .viewModifier }
    if inherited.contains("View") { return .view }
    return .none
}

/// Adds a nested `StatelessNode` struct plus a `statelessNode` computed property to the
/// struct, class, or actor it's attached to — the same field set `@DataLayout`'s
/// own `OutFlow`/`outFlow` capture (every non-private participating property,
/// plus private `@Environment`/`@Query`/`@State`/`@AppStorage` state), as a real
/// nominal type instead of a tuple.
///
/// A separate macro from `@DataLayout` — doesn't replace `OutFlow`/`outFlow`, and
/// works with or without `@DataLayout` also attached, since it collects the
/// type's stored properties itself.
///
/// When the attached type's own inheritance clause spells `View` or
/// `ViewModifier` (`detectHostKind`), `StatelessNode` is additionally declared to
/// conform to the same protocol, and the attached type gets one more generated
/// member: the mechanical delegation from the real `body`/`body(content:)`
/// requirement down to `self.statelessNode` — `var body: some View { self.statelessNode }`
/// for `View`, `func body(content: Content) -> some View {
/// content.modifier(self.statelessNode) }` for `ViewModifier` (via `View.modifier(_:)`,
/// which needs no `Content`-type unification between the two types' independent
/// `ViewModifier.Content`s — verified directly that forwarding `content` straight
/// into `StatelessNode`'s own `body(content:)` instead does *not* compile: `Content`
/// is `typealias Content = _ViewModifier_Content<Self>`, keyed to the conforming
/// type itself, so two different conforming types' `Content`s are unrelated
/// concrete types no constraint can unify). `StatelessNode` conforming to the
/// protocol only *declares* the requirement — its actual `body`/`body(content:)`
/// implementation is left for hand-written code in a separate extension, same as
/// every other `@DataLayout`/`@StatelessNode` member split between generated
/// boilerplate and hand-written logic elsewhere in this package.
///
/// Entry-point boilerplate is `validatedProperties`, shared with `@DataLayout`;
/// `renderStatelessNode` (in `StatelessNodeRendering.swift`) does the actual work, reusing
/// `@DataLayout`'s own `outFlowProperties`/`outFlowFieldType`/
/// `outFlowFieldReadExpression` (`DataLayoutRendering.swift`) rather than
/// re-deriving the same field set.
public enum StatelessNodeMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard
            let (properties, access) = validatedProperties(
                of: declaration, attachedTo: node, macroName: "StatelessNode", in: context
            )
        else {
            return []
        }
        return renderStatelessNode(
            properties: properties, access: access, hostKind: detectHostKind(of: declaration))
    }
}
