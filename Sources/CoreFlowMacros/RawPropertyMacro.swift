import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// The `raw_` accessor exposing a wrapper's synthesized `private _name`
/// backing storage at internal access — Swift hardcodes that storage private
/// with no way to loosen it, so once the enclosing struct exists the wrapper
/// instance itself can't be swapped from outside; this is the escape hatch
/// (`var copy = shell.core; copy.raw_isOn = .constant(false)`).
func renderRawAccessor(name: String, wrapperType: String) -> String {
    """
    var raw_\(name): \(wrapperType) {
        get {
            _\(name)
        }
        set {
            _\(name) = newValue
        }
    }
    """
}

/// Peer macro exposing a property wrapper's synthesized `private _name`
/// backing storage at internal access: `@RawProperty @Binding var isOn: Bool`
/// generates `var raw_isOn: Binding<Bool> { get { _isOn } set { _isOn = newValue } }`.
///
/// The wrapper type is inferred syntax-only, like everything in this package:
/// an attribute written with generics (`@Binding<Bool>`) is used verbatim;
/// otherwise the binding's type annotation fills the generic
/// (`@Binding var isOn: Bool` → `Binding<Bool>`); otherwise a diagnostic asks
/// for an annotation. The first attribute that isn't `@RawProperty` itself is
/// taken as the wrapper — no attribute at all is an error (there's no backing
/// storage to expose).
public enum RawPropertyMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard
            let varDecl = declaration.as(VariableDeclSyntax.self),
            let binding = varDecl.bindings.first,
            let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
            binding.accessorBlock.map({ !isComputed($0) }) ?? true,
            let wrapper = varDecl.attributes.compactMap({ item -> AttributeSyntax? in
                guard case .attribute(let attr) = item,
                    attr.attributeName.trimmedDescription != "RawProperty"
                else { return nil }
                return attr
            }).first
        else {
            context.diagnose(
                Diagnostic(
                    node: node, message: RawPropertyDiagnostic.notAWrappedStoredProperty))
            return []
        }
        let name = pattern.identifier.text

        // @Binding<Bool> — generics written on the attribute itself, verbatim.
        // Otherwise the annotation fills the generic: @Binding var x: Bool → Binding<Bool>.
        let wrapperType: String
        let attributeText = wrapper.attributeName.trimmedDescription
        if attributeText.contains("<") {
            wrapperType = attributeText
        } else if let annotated = binding.typeAnnotation?.type {
            wrapperType = "\(attributeText)<\(annotated.trimmedDescription)>"
        } else {
            context.diagnose(
                Diagnostic(node: node, message: RawPropertyDiagnostic.uninferrableWrapperType(name))
            )
            return []
        }

        return [DeclSyntax(stringLiteral: renderRawAccessor(name: name, wrapperType: wrapperType))]
    }
}

// MARK: - Diagnostics

struct RawPropertyDiagnostic: DiagnosticMessage {
    let message: String
    let id: String
    var severity: DiagnosticSeverity { .error }

    var diagnosticID: MessageID {
        MessageID(domain: "CoreFlow", id: id)
    }

    static let notAWrappedStoredProperty = RawPropertyDiagnostic(
        message:
            "@RawProperty can only be attached to a stored property that also has a property wrapper attribute — there's no backing storage to expose otherwise.",
        id: "notAWrappedStoredProperty"
    )

    static func uninferrableWrapperType(_ name: String) -> RawPropertyDiagnostic {
        RawPropertyDiagnostic(
            message:
                "'\(name)' needs an explicit type annotation (or generics on the wrapper attribute) so @RawProperty can spell the backing storage's type.",
            id: "uninferrableWrapperType"
        )
    }
}
