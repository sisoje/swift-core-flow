import SwiftSyntax
import SwiftSyntaxMacros

/// Adds BOTH the `@MemberwiseInit` and `@DataLayoutInit` initializers at once, at the
/// type's own access level — see the doc comment on `@DataInit` (in
/// `Sources/DataMacros/DataInit.swift`) for the full picture.
///
/// Collects stored properties exactly once (`validatedProperties`, shared with the
/// other two macros) and renders both shapes from that single pass —
/// `renderMemberwiseInit` and `renderDataLayoutMembers` — rather than stacking
/// `@DataLayoutInit @MemberwiseInit`, which would collect (and diagnose) the same
/// properties twice. The two generated initializers never collide: one property each
/// (`init(x:y:)`) vs. one tuple (`init(_:)`) are different signatures at every
/// property count *except* zero, where both renderers would independently emit a
/// bare `init()` — that one case is special-cased below to emit it just once.
public enum DataInitMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard
            let (properties, access) = validatedProperties(
                of: declaration, attachedTo: node, macroName: "DataInit", in: context
            )
        else {
            return []
        }

        guard properties.contains(where: { !$0.isPrivate }) else {
            // Both renderers would independently emit the same `init() {}` — collapse
            // to one to avoid "invalid redeclaration of 'init()'".
            return [DeclSyntax(stringLiteral: "\(access)init() {}")]
        }

        return renderMemberwiseInit(properties: properties, access: access)
            + renderDataLayoutMembers(properties: properties, access: access)
    }
}
