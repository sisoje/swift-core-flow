import SwiftSyntax
import SwiftSyntaxMacros

/// Adds a memberwise `init` to the struct, class, or actor it is attached to, at the
/// type's own access level — plus the `InFlowSplat`/`InFlow`/`OutFlow`
/// typealiases and their `makeFlow(_:)`/`inFlow`/`outFlow` accessors alongside it.
///
/// Swift only *synthesizes* an `internal` memberwise initializer for a struct, and
/// only when you write no init of your own; a class or actor gets none at all. This
/// member macro writes an explicit one that matches the type — so a `public struct`
/// gets the `public init` Swift won't synthesize, and an `@Observable final class`
/// gets the memberwise `init` it otherwise needs by hand.
///
/// Entry-point boilerplate is `validatedProperties`; `renderFlowable` does the
/// actual work (including every typealias/accessor — see the doc comments in
/// `FlowableRendering.swift`). This type is just the `MemberMacro` conformance.
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
