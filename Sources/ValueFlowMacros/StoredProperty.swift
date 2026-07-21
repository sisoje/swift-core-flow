import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - Stored-property model

/// A stored property that participates in `@DataLayout`'s generated init and
/// `DataLayout` typealias.
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

    /// `@Binding` is the one property wrapper threaded through (as a projected
    /// `Binding<T>`). Every other wrapper is view-owned or injected (`@State`,
    /// `@Environment`, `@StateObject`, …) and self-initializes.
    public var isBinding: Bool {
        wrapperName == "Binding"
    }

    /// `@ViewBuilder` — the parameter carries the attribute so callers get trailing
    /// builder syntax. When the property stores the built value (`let vb: Content`)
    /// the parameter is a `() -> Content` the init calls; when it stores the closure
    /// (`let vb: () -> Content`) the parameter is that `@escaping` closure.
    public var isViewBuilder: Bool {
        wrapperName == "ViewBuilder"
    }

    /// `@Environment` — `@StatelessNode`'s field is a plain `let` of the property's
    /// own declared type, no attribute at all (unlike `@State`/`@AppStorage`,
    /// which keep `@Binding`). Not because the value doesn't change — because
    /// the *attribute* can't be preserved: `@Environment`'s `wrappedValue` has
    /// no public setter (verified directly: `error: cannot assign to property:
    /// 'colorScheme' is a get-only property`), and `@DataLayout`'s init always
    /// assigns `self.x = x` — a plain, unattributed `let` has no such
    /// restriction, so the value is captured once, like every other field.
    public var isEnvironment: Bool {
        wrapperName == "Environment"
    }

    /// `@Query` (SwiftData) — `@StatelessNode`'s field is always synthesized as
    /// `(result: WrappedType, fetchError: Error?, modelContext: ModelContext)`,
    /// regardless of the property's own declared type. `WrappedType` is the
    /// property's own declared type (e.g. `[Item]` for `@Query private var
    /// items: [Item]`); `fetchError` and `modelContext` are real members of
    /// SwiftData's `Query` wrapper *instance* (reached via the
    /// underscore-prefixed backing storage), not synthesized placeholders —
    /// verified directly against the SwiftData interface.
    public var isQuery: Bool {
        wrapperName == "Query"
    }

    /// `@State`/`@AppStorage` — the two wrappers `@StatelessNode` declares as a real
    /// `@Binding var` property (bare wrapped type, not `Binding<T>`), read via
    /// the projected `$` value (not `_`, which gives the wrapper instance itself
    /// — `State<T>`, not `Binding<T>`). Unlike `isEnvironment`/`isQuery` above,
    /// these are the view's own externally read-*and-write*-able storage — their
    /// own storage only installs inside a live SwiftUI view, so they can't be
    /// redeclared as themselves on a plain struct; `@Binding` is the
    /// injectable/settable substitute.
    public var isStateOrAppStorage: Bool {
        wrapperName == "State" || wrapperName == "AppStorage"
    }
}

// MARK: - Collection

/// Collect the stored properties of a struct/class/actor that participate in a
/// generated initializer.
///
/// Skips computed properties, `static`/`class` members, and non-identifier bindings
/// (tuple destructuring). Returns `nil` if a diagnostic was emitted — an init
/// parameter lacking an explicit type (this is syntax-only and can't infer it).
/// `macroName` (e.g. `"DataLayout"`) names the attribute in the diagnostic.
public func collectStoredProperties(
    of decl: some DeclGroupSyntax,
    in context: some MacroExpansionContext,
    macroName: String
) -> [StoredProperty]? {
    var properties: [StoredProperty] = []
    var hadError = false

    for member in decl.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

        // Skip static / class members — not part of a generated init.
        let isStatic = varDecl.modifiers.contains {
            $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        }
        if isStatic { continue }

        let isPrivate = varDecl.modifiers.contains {
            $0.name.tokenKind == .keyword(.private) || $0.name.tokenKind == .keyword(.fileprivate)
        }

        let isLet = varDecl.bindingSpecifier.tokenKind == .keyword(.let)

        for binding in varDecl.bindings {
            // Only simple identifier patterns (no tuple destructuring).
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }

            // Skip computed properties (a getter accessor block). Stored properties
            // with only willSet/didSet observers are kept, observers dropped.
            if let accessorBlock = binding.accessorBlock, isComputed(accessorBlock) { continue }

            let property = StoredProperty(
                name: pattern.identifier.text,
                type: binding.typeAnnotation?.type,
                isLet: isLet,
                defaultValue: binding.initializer?.value,
                wrapperName: propertyWrapperName(varDecl.attributes),
                isPrivate: isPrivate
            )

            // @State/@Environment/@Query/@AppStorage are each a view's own
            // source of truth — never something a caller supplies (that's what
            // @Binding is for) — so they must be private. Enforced here, not
            // accommodated later: every renderer downstream can assume these
            // four are always private, with no "what if it's also public" case
            // to reason about or test.
            let isSourceOfTruth =
                property.isEnvironment || property.isQuery || property.isStateOrAppStorage
            if isSourceOfTruth, !property.isPrivate {
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

            // Init parameters need a written type; so do @Environment/@Query/@State/
            // @AppStorage properties, even though they're excluded from *this*
            // type's own init — @StatelessNode (see StatelessNodeRendering.swift) reads
            // their type to build its field (all four eventually get folded into
            // StatelessNode's own init, as a plain captured value or a @Binding
            // substitute). Every other private property — inline-initialized
            // `let` constants, plain private state — is exempt (`private var ole = 0`
            // needs no annotation and doesn't participate in either).
            let needsType =
                !property.isPrivate || property.isEnvironment || property.isQuery
                || property.isStateOrAppStorage
            if needsType, property.type == nil {
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
/// `macroName` (e.g. `"DataLayout"`) names the offending attribute in the
/// message.
public struct DataTypeMacroDiagnostic: DiagnosticMessage {
    public let message: String
    public let id: String
    public var severity: DiagnosticSeverity { .error }

    public var diagnosticID: MessageID {
        MessageID(domain: "ValueFlow", id: id)
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
                "'\(propertyName)' must be private — @State/@Environment/@Query/@AppStorage are a view's own source of truth, not something a caller supplies (use @Binding for that).",
            id: "sourceOfTruthMustBePrivate"
        )
    }
}
