import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Validates that `declaration` is a struct, class, or actor and collects its stored
/// properties — diagnosing (and returning nil) on either failure. The shared
/// entry-point boilerplate for every member macro that generates an init from stored
/// properties (`@MemberwiseInit`, `@DataLayoutInit`, `@DataInit`): each macro's
/// `expansion` reduces to calling this and then rendering.
func validatedProperties(
    of declaration: some DeclGroupSyntax,
    attachedTo node: AttributeSyntax,
    macroName: String,
    in context: some MacroExpansionContext
) -> (properties: [StoredProperty], access: String)? {
    guard
        declaration.is(StructDeclSyntax.self) || declaration.is(ClassDeclSyntax.self)
            || declaration.is(ActorDeclSyntax.self)
    else {
        context.diagnose(
            Diagnostic(node: node, message: DataTypeMacroDiagnostic.notADataType(macroName: macroName))
        )
        return nil
    }
    guard
        let properties = collectStoredProperties(of: declaration, in: context, macroName: macroName)
    else {
        return nil
    }
    return (properties, accessLevel(of: declaration))
}
