import SwiftSyntax
import SwiftSyntaxMacros

/// Adds an init that takes the type's stored properties as one tuple-typed
/// `dataLayout` parameter, at the type's own access level. See the doc comment on
/// `@DataLayoutInit` (in `Sources/DataMacros/DataLayoutInit.swift`) for the full
/// picture.
///
/// Entry-point boilerplate (`validatedProperties`) and rendering
/// (`renderDataLayoutMembers`) are both shared with `@DataInit`. This type is just
/// the `MemberMacro` conformance.
public enum DataLayoutInitMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard
            let (properties, access) = validatedProperties(
                of: declaration, attachedTo: node, macroName: "DataLayoutInit", in: context
            )
        else {
            return []
        }
        return renderDataLayoutMembers(properties: properties, access: access)
    }
}
