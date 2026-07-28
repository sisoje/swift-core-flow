import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - Stored-property model

/// A stored property that participates in `@Flowable`'s generated init and
/// `InFlowSplat`/`InFlow` typealiases (and `@Shell`'s `Core`).
public struct StoredProperty {
    public let name: String
    public let type: TypeSyntax?
    public let isLet: Bool
    public let defaultValue: ExprSyntax?
    /// The property-wrapper type name (`Binding`, `State`, `Environment`, …), or nil.
    public let wrapperName: String?
    /// True if the property is declared `private` or `fileprivate` — implementation
    /// detail, excluded from the init. This is also what keeps view-owned wrappers
    /// out: `@State`, `@Environment`, … are always private.
    public let isPrivate: Bool
    /// The raw declaration this property was collected from (`binding` is the
    /// one pattern binding it covers). `@Shell`'s verbatim copies render from
    /// these nodes alone (`ShellRendering.swift`); the parsed fields above are
    /// `@Flowable`'s init/typealias channel and the substituted rows' — the
    /// two never mix.
    public let varDecl: VariableDeclSyntax
    public let binding: PatternBindingSyntax

    /// The one wrapper threaded through the init, as its projected `Binding<T>`.
    public var isBinding: Bool {
        wrapperName == "Binding"
    }

    /// Not a property wrapper — a result-builder attribute; it reshapes only
    /// the init parameter (see `baseTypeText`), never the storage.
    public var isViewBuilder: Bool {
        wrapperName == "ViewBuilder"
    }

    /// The kinds a caller supplies through the generated init — declaring one
    /// private makes it unreachable, hence the dedicated diagnostic. (Other
    /// non-private wrappers need no case: plain `self.x = x` in the init,
    /// verbatim copy on `Core`.)
    public var isCallerSuppliedWrapper: Bool {
        isBinding || isViewBuilder
    }

    /// THE mapping whitelist — the only wrappers this package really knows,
    /// exactly the ones `sourceOfTruthMustBePrivate` requires private. Why
    /// exactly these and no others: `renderShell`'s rule-1 comment.
    public var isSubstitutedOnCore: Bool {
        isOwnState || isExternalStorage || isQuery
    }

    /// `@Query` → `@QueryCore` on `Core` (`QueryCore.swift` documents the
    /// one-to-one surface).
    public var isQuery: Bool {
        wrapperName == "Query"
    }

    /// The view's OWN state → `@TestState private` on `Core`: the host's
    /// line with the wrapper renamed — same default, every mutation logged.
    public var isOwnState: Bool {
        wrapperName == "State"
    }

    /// EXTERNAL storage — a dependency, injected as `@Binding` on `Core`:
    /// same shape (settable `wrappedValue`, `projectedValue` genuinely *is*
    /// `Binding<T>` — verified directly), and their storage installs only
    /// inside a live view, so they can't be redeclared on a plain struct.
    public var isExternalStorage: Bool {
        wrapperName == "AppStorage" || wrapperName == "SceneStorage"
    }
}

// MARK: - Collection

/// Skips computed properties, `static`/`class` members, and tuple
/// destructuring; nil if a diagnostic was emitted. `macroName` names the
/// attribute in diagnostics.
public func collectStoredProperties(
    of decl: some DeclGroupSyntax,
    in context: some MacroExpansionContext,
    macroName: String
) -> [StoredProperty]? {
    var properties: [StoredProperty] = []
    var hadError = false

    for member in decl.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

        let isStatic = varDecl.modifiers.contains {
            $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        }
        if isStatic { continue }

        // `private(set)`/`fileprivate(set)` land here too — deliberately not
        // special-cased: setter-restricted properties have no place in pure data
        // flow, and the plain-private diagnostic below already rejects them.
        let isPrivate = varDecl.modifiers.contains {
            $0.name.tokenKind == .keyword(.private) || $0.name.tokenKind == .keyword(.fileprivate)
        }

        let isLet = varDecl.bindingSpecifier.tokenKind == .keyword(.let)

        for binding in varDecl.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }

            // Stored properties with only willSet/didSet observers are kept.
            if let accessorBlock = binding.accessorBlock, isComputed(accessorBlock) { continue }

            let wrapperName = propertyWrapperName(varDecl.attributes)
            let explicitType = binding.typeAnnotation?.type
            let inferredType: TypeSyntax?
            if let explicitType {
                inferredType = explicitType
            } else if wrapperName == "Namespace" {
                // The one wrapper with exactly one possible wrapped type — no
                // generic parameter to resolve — so a bare `@Namespace private
                // var ns` needs no annotation and no type checker.
                inferredType = "Namespace.ID"
            } else {
                inferredType = binding.initializer.flatMap { inferredLiteralType($0.value) }
            }

            let property = StoredProperty(
                name: pattern.identifier.text,
                type: inferredType,
                isLet: isLet,
                defaultValue: binding.initializer?.value,
                wrapperName: wrapperName,
                isPrivate: isPrivate,
                varDecl: varDecl,
                binding: binding
            )

            // A source of truth is a view's own, never caller-supplied
            // (@Binding is for that) — enforced here so every renderer
            // downstream can assume the substituted set is private, no
            // "what if it's also public" case. Unknown wrappers carry no
            // privacy rule: copied verbatim either way; a non-private one is
            // an ordinary init parameter.
            if property.isSubstitutedOnCore, !property.isPrivate {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(binding),
                        message: DataTypeMacroDiagnostic.sourceOfTruthMustBePrivate(
                            macroName: macroName, propertyName: property.name
                        )
                    )
                )
                hadError = true
                continue
            }

            // @Binding/@ViewBuilder are the opposite of a source-of-truth
            // wrapper: a caller supplies them through the generated init, so
            // declaring one private makes it unreachable.
            if property.isPrivate, property.isCallerSuppliedWrapper {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(binding),
                        message: DataTypeMacroDiagnostic.callerSuppliedWrapperMustNotBePrivate(
                            macroName: macroName, propertyName: property.name,
                            wrapperName: wrapperName!
                        )
                    )
                )
                hadError = true
                continue
            }

            // @ViewBuilder content is caller-supplied and never reassigned —
            // `var` is refused.
            if property.isViewBuilder, !property.isLet {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(binding),
                        message: DataTypeMacroDiagnostic.viewBuilderMustBeLet(
                            macroName: macroName, propertyName: property.name
                        )
                    )
                )
                hadError = true
                continue
            }

            // A private property with no property wrapper at all is opaque
            // view-owned state that's neither a source of truth nor something
            // a caller supplies — pure data flow has no room for it, so it
            // fails loudly instead of being silently excluded.
            if property.isPrivate, property.wrapperName == nil {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(binding),
                        message: DataTypeMacroDiagnostic.plainPrivatePropertyNotAllowed(
                            macroName: macroName, propertyName: property.name
                        )
                    )
                )
                hadError = true
                continue
            }

            // Private wrapper fields need a written type too, not just init
            // parameters: `Core` reads it to declare the substituted field.
            // (@Namespace never trips this — pre-filled above.)
            if property.type == nil {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(binding),
                        message: DataTypeMacroDiagnostic.missingType(
                            macroName: macroName, propertyName: property.name
                        )
                    )
                )
                hadError = true
                continue
            }

            properties.append(property)
        }
    }

    return hadError ? nil : properties
}

// MARK: - Helpers

/// The type's access modifier as a trailing-spaced prefix (`"public "`,
/// `"package "`, …), or `""` for the default internal.
public func accessLevel(of decl: some DeclGroupSyntax) -> String {
    let accessKeywords: Set<TokenKind> = [
        .keyword(.public), .keyword(.package), .keyword(.internal),
        .keyword(.fileprivate), .keyword(.private),
    ]
    let modifier = decl.modifiers.first { accessKeywords.contains($0.name.tokenKind) }
    return modifier.map { "\($0.name.text) " } ?? ""
}

/// The name of the first attribute on a property (its property-wrapper type, e.g.
/// `Binding` for `@Binding`), or nil if the property carries no attributes.
public func propertyWrapperName(_ attributes: AttributeListSyntax) -> String? {
    for case .attribute(let attr) in attributes {
        if let name = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text {
            return name
        }
    }
    return nil
}

/// True if a type is a function type (plain, attributed, or parenthesized). Optional
/// function types (`(() -> Void)?`) are deliberately *not* matched: an optional closure
/// is already escaping, and `@escaping` on it is a compile error.
public func isFunctionType(_ type: TypeSyntax) -> Bool {
    if type.is(FunctionTypeSyntax.self) { return true }
    // Attributed function types, e.g. `@MainActor () -> Void` or `@Sendable () -> Void`.
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return isFunctionType(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self),
        tuple.elements.count == 1,
        let inner = tuple.elements.first?.type
    {
        return isFunctionType(inner)
    }
    return false
}

/// True if a type is optional (`T?` or `T!`) — a `var` of such a type is implicitly
/// nil-initialized.
public func isOptionalType(_ type: TypeSyntax) -> Bool {
    type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
}

/// Infers a type from a simple literal default (`false`, `0`, `"x"`) — the only
/// three literal kinds unambiguous enough to recognize without a real type
/// checker (no numeric-literal-defaults-to-Double, no protocol witness
/// resolution). Returns nil for anything else — a call, an identifier, `nil`, a
/// collection literal, … — leaving those to the missing-type diagnostic.
public func inferredLiteralType(_ expr: ExprSyntax) -> TypeSyntax? {
    if expr.is(BooleanLiteralExprSyntax.self) { return "Bool" }
    if expr.is(IntegerLiteralExprSyntax.self) { return "Int" }
    if expr.is(StringLiteralExprSyntax.self) { return "String" }
    return nil
}

/// True if an accessor block represents a computed property (a getter), as opposed
/// to a stored property carrying only `willSet` / `didSet` observers.
public func isComputed(_ accessorBlock: AccessorBlockSyntax) -> Bool {
    switch accessorBlock.accessors {
    case .getter:
        return true
    case .accessors(let list):
        return list.contains { $0.accessorSpecifier.tokenKind == .keyword(.get) }
    }
}

// MARK: - Diagnostics

/// Shared diagnostics for member macros generating an init from stored properties.
/// `macroName` (e.g. `"Flowable"`) names the offending attribute in the
/// message.
public struct DataTypeMacroDiagnostic: DiagnosticMessage {
    public let message: String
    public let id: String
    public var severity: DiagnosticSeverity { .error }

    public var diagnosticID: MessageID {
        MessageID(domain: "CoreFlow", id: id)
    }

    public static func notADataType(macroName: String) -> DataTypeMacroDiagnostic {
        DataTypeMacroDiagnostic(
            message: "@\(macroName) can only be attached to a struct, class, or actor.",
            id: "notADataType"
        )
    }

    public static func missingType(macroName: String, propertyName: String)
        -> DataTypeMacroDiagnostic
    {
        DataTypeMacroDiagnostic(
            message:
                "Stored property '\(propertyName)' needs an explicit type annotation so @\(macroName) can generate the initializer/stateless snapshot.",
            id: "missingType"
        )
    }

    public static func sourceOfTruthMustBePrivate(macroName: String, propertyName: String)
        -> DataTypeMacroDiagnostic
    {
        DataTypeMacroDiagnostic(
            message:
                "'\(propertyName)' must be private — @State/@AppStorage/@SceneStorage/@Query are a view's own source of truth, not something a caller supplies (use @Binding for that).",
            id: "sourceOfTruthMustBePrivate"
        )
    }

    public static func plainPrivatePropertyNotAllowed(macroName: String, propertyName: String)
        -> DataTypeMacroDiagnostic
    {
        DataTypeMacroDiagnostic(
            message:
                "'\(propertyName)' is private with no property wrapper — @\(macroName) has no room for opaque private state in pure data flow. Make it non-private, or give it a property wrapper (mapped ones are substituted with mockable stand-ins; any other is copied onto Core verbatim).",
            id: "plainPrivatePropertyNotAllowed"
        )
    }

    public static func callerSuppliedWrapperMustNotBePrivate(
        macroName: String, propertyName: String, wrapperName: String
    )
        -> DataTypeMacroDiagnostic
    {
        DataTypeMacroDiagnostic(
            message:
                "'\(propertyName)' uses @\(wrapperName), which a caller supplies through @\(macroName)'s generated init — declaring it private makes it unreachable. Remove `private`/`fileprivate` from '\(propertyName)'.",
            id: "callerSuppliedWrapperMustNotBePrivate"
        )
    }

    public static func viewBuilderMustBeLet(macroName: String, propertyName: String)
        -> DataTypeMacroDiagnostic
    {
        DataTypeMacroDiagnostic(
            message:
                "'\(propertyName)' must be a `let` — @ViewBuilder content is caller-supplied through @\(macroName)'s generated init and never reassigned.",
            id: "viewBuilderMustBeLet"
        )
    }

    /// `@Shell`'s own rule, checked in `ShellMacro` rather than the shared
    /// collection — `@Flowable` renders nothing from a private `@State`, so
    /// it has no stake in the default.
    public static func stateNeedsInlineDefault(propertyName: String)
        -> DataTypeMacroDiagnostic
    {
        DataTypeMacroDiagnostic(
            message:
                "'\(propertyName)' needs an inline default — @Shell re-declares @State as @TestState on Core and copies the default.",
            id: "stateNeedsInlineDefault"
        )
    }

}
