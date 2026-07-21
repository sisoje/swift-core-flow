import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Validates that `declaration` is a struct, class, or actor and collects its stored
/// properties — diagnosing (and returning nil) on either failure. `@DataLayout`'s
/// `expansion` reduces to calling this and then rendering; kept as its own function
/// (rather than inlined) since any future macro generating both an init and a
/// `DataLayout`-style typealias from stored properties would want the exact same
/// validate-then-collect shape.
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
            Diagnostic(
                node: node, message: DataTypeMacroDiagnostic.notADataType(macroName: macroName))
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
