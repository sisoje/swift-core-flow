import SwiftSyntax
import SwiftSyntaxMacros

/// The memberwise init Swift won't synthesize — internal-only for structs,
/// none at all for a class/actor (an `@Observable final class` otherwise
/// writes one by hand) — plus `makeFlow(_:)`/`InFlow`.
/// Entry point only; `renderFlowable` (`FlowableRendering.swift`) documents
/// the rules.
public enum FlowableMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard
            let (properties, access) = validatedProperties(
                of: declaration, attachedTo: node, macroName: "Flowable", in: context
            )
        else {
            return []
        }
        return renderFlowable(properties: properties, access: access)
    }
}
