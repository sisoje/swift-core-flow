import SwiftSyntax
import SwiftSyntaxMacros

/// Adds a memberwise `init` to the struct, class, or actor it is attached to, at the
/// type's own access level.
///
/// Swift only *synthesizes* an `internal` memberwise initializer for a struct, and
/// only when you write no init of your own; a class or actor gets none at all. This
/// member macro writes an explicit one that matches the type — so a `public struct`
/// gets the `public init` Swift won't synthesize, and an `@Observable final class`
/// gets the memberwise `init` it otherwise needs by hand.
///
/// Entry-point boilerplate (`validatedProperties`) is shared with `@DataLayoutInit`;
/// `renderMemberwiseInit` does the actual work. This type is just the `MemberMacro`
/// conformance.
public enum MemberwiseInitMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard
            let (properties, access) = validatedProperties(
                of: declaration, attachedTo: node, macroName: "MemberwiseInit", in: context
            )
        else {
            return []
        }
        return renderMemberwiseInit(properties: properties, access: access)
    }
}
