import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// The shared validate-then-collect entry for every macro generating members
/// from stored properties (`@Flowable`, `@Shell`, future ones).
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
