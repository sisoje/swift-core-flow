import SwiftSyntax
import SwiftSyntaxMacros

/// `@FlowUp var handleUrl: (URL) async throws -> Void` — one line inside a
/// user-written `extension EnvironmentValues` declares an upward closure
/// flow. The anchor's accessor becomes the consumer entry: a genuine
/// closure calling every registered listener in order, built over the
/// hidden storage. Peers: a key enum that is both the `EnvironmentKey` and
/// the per-name tag keying the preference channel (hand-rolled — native
/// `@Entry` refuses to expand inside another macro's expansion buffer: its
/// container check cannot see the extension from there, verified
/// directly), the fileprivate settable entry holding the bare wrapper
/// array, and a same-named `static` `FlowUpID`
/// (legal — static and instance members may share a name) that `on` /
/// `accumulate` resolve through a metatype-rooted keypath, so one name
/// spells every call site.
///
/// The anchor's declared access level is copied onto the key enum and the
/// static — the static's return type names the key-as-tag, so exporting a
/// flow needs both public. The entry stays fileprivate regardless:
/// keypaths carry the access rights of where they were formed.
///
/// Required shape: a stored instance `var` with a function-type annotation
/// returning `Void` and no initial value — anything else THROWS, a compile
/// error at the attribute (the family-wide policy: a silently skipped
/// declaration could compile as a plain, unmanaged property).
public enum FlowUpMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        let anchor = try validated(declaration, in: context)
        let arguments = (0..<anchor.parameterCount).map { "a\($0)" }.joined(separator: ", ")
        let signature = arguments.isEmpty ? "" : " \(arguments) in"
        return [
            """
            get {
                let wrappers = self.\(raw: anchor.name)_closures
                return {\(raw: signature)
                    for wrapper in wrappers {
                        for closure in wrapper.closures {
                            \(raw: anchor.effects)closure(\(raw: arguments))
                        }
                    }
                }
            }
            """
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // The accessor role reports the error; throwing here too would
        // duplicate it.
        guard let anchor = try? validated(declaration, in: context) else { return [] }
        let typeText = anchor.closureType.trimmedDescription
        return [
            """
            \(raw: anchor.access)enum \(raw: anchor.name)_Key: EnvironmentKey {
                \(raw: anchor.access)static var defaultValue: [FlowUpClosure<\(raw: typeText)>] {
                    []
                }
            }
            """,
            """
            fileprivate var \(raw: anchor.name)_closures: [FlowUpClosure<\(raw: typeText)>] {
                get {
                    self[\(raw: anchor.name)_Key.self]
                }
                set {
                    self[\(raw: anchor.name)_Key.self] = newValue
                }
            }
            """,
            """
            \(raw: anchor.access)static var \(raw: anchor.name): FlowUpID<\(raw: anchor.name)_Key, \(raw: typeText)> {
                FlowUpID(keyPath: \\.\(raw: anchor.name)_closures)
            }
            """,
        ]
    }

    private struct Anchor {
        let name: String
        let closureType: TypeSyntax
        let parameterCount: Int
        let effects: String
        let access: String
    }

    /// The anchor's (name, full annotated closure type, arity, effects,
    /// access) — any other shape throws, a compile error at the attribute
    /// stating the required shape. The function type is found under any
    /// type attributes (`@MainActor (URL) -> Void`), which ride the full
    /// type text verbatim into every generic position.
    private static func validated(
        _ declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> Anchor {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
            !isStatic(varDecl),
            varDecl.bindingSpecifier.tokenKind == .keyword(.var),
            varDecl.bindings.count == 1, let binding = varDecl.bindings.first,
            let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
            binding.accessorBlock == nil,
            binding.initializer == nil,
            let annotation = binding.typeAnnotation?.type,
            let functionType = bareFunctionType(annotation)
        else {
            throw MacroExpansionErrorMessage(
                "@FlowUp requires a stored instance 'var' with a function-type annotation and no initial value."
            )
        }
        guard isVoid(functionType.returnClause.type) else {
            throw MacroExpansionErrorMessage(
                "@FlowUp requires a 'Void'-returning closure type: N listeners have no single combined result."
            )
        }
        if let extensionDecl = context.lexicalContext.first?.as(ExtensionDeclSyntax.self),
            extensionDecl.extendedType.as(IdentifierTypeSyntax.self)?.name.text
                != "EnvironmentValues"
        {
            throw MacroExpansionErrorMessage(
                "@FlowUp must be attached inside 'extension EnvironmentValues'."
            )
        }
        var effects = ""
        if functionType.effectSpecifiers?.throwsClause != nil { effects += "try " }
        if functionType.effectSpecifiers?.asyncSpecifier != nil { effects += "await " }
        let access =
            varDecl.modifiers.first { accessKeywords.contains($0.name.tokenKind) }
            .map { "\($0.trimmedDescription) " } ?? ""
        return Anchor(
            name: pattern.identifier.text,
            closureType: annotation,
            parameterCount: functionType.parameters.count,
            effects: effects,
            access: access
        )
    }

    /// The function type under any type attributes; `nil` for anything
    /// that is not a function type.
    private static func bareFunctionType(_ type: TypeSyntax) -> FunctionTypeSyntax? {
        if let functionType = type.as(FunctionTypeSyntax.self) { return functionType }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return bareFunctionType(attributed.baseType)
        }
        return nil
    }

    private static func isVoid(_ type: TypeSyntax) -> Bool {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text == "Void"
        }
        if let tuple = type.as(TupleTypeSyntax.self) { return tuple.elements.isEmpty }
        return false
    }

    private static let accessKeywords: [TokenKind] = [
        .keyword(.public), .keyword(.package), .keyword(.internal),
        .keyword(.fileprivate), .keyword(.private),
    ]
}
