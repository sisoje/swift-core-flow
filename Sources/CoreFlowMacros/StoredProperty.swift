import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - Stored-property model

/// A stored property that participates in `@Flowable`'s generated init and
/// `InFlowSplat`/`InFlow`/`OutFlow` typealiases (and `@Shell`'s `Core`).
public struct StoredProperty {
    public let name: String
    public let type: TypeSyntax?
    public let isLet: Bool
    public let defaultValue: ExprSyntax?
    /// The property-wrapper type name (`Binding`, `State`, `Environment`, …), or nil.
    public let wrapperName: String?
    /// The property's own attribute list, source text verbatim (e.g.
    /// `@GestureState(reset: { _, transaction in transaction = Transaction() })`),
    /// or nil if it carries no attributes. This is what `renderShell`
    /// (`ShellRendering.swift`) splices when copying an unmapped wrapper's
    /// declaration onto `Core` byte-for-byte — whatever lives in the
    /// attribute's own arguments (a reset closure, a key path, a
    /// `relativeTo:`) can't be reconstructed from the bare wrapper name.
    public let attributeText: String?
    /// True if the property is declared `private` or `fileprivate` — implementation
    /// detail, excluded from the init. This is also what keeps view-owned wrappers
    /// out: `@State`, `@Environment`, … are always private.
    public let isPrivate: Bool

    /// `@Binding` is the one property wrapper threaded through (as a projected
    /// `Binding<T>`). Every recognized source-of-truth wrapper (`@State`,
    /// `@Environment`, …) is view-owned and self-initializes; anything
    /// unrecognized (`@StateObject`, …) is refused outright.
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

    /// `@Binding`/`@ViewBuilder` — the wrapper/attribute kinds a caller
    /// supplies through the generated init, the opposite of a source-of-truth
    /// wrapper. Declaring one private makes it unreachable (a caller could
    /// never supply it), so it's rejected with its own diagnostic. (Any other
    /// non-private wrapper — `@Bindable`, a custom one — needs no dedicated
    /// case: the ordinary `self.x = x` assignment path handles it in the
    /// init, and `Core` copies its declaration verbatim.)
    public var isCallerSuppliedWrapper: Bool {
        isBinding || isViewBuilder
    }

    /// THE mapping whitelist — the only wrapper kinds this package really
    /// knows, and exactly the ones `sourceOfTruthMustBePrivate` requires
    /// private. `@Shell` substitutes each on `Core` with a mockable stand-in;
    /// every other wrapper — `@Binding` included — is copied onto `Core`
    /// verbatim (see `renderShell`). The list is exactly the wrappers where a
    /// substitution buys a REAL mock, and nothing else: for
    /// `@State`/`@AppStorage`/`@SceneStorage`, a test-supplied
    /// `Binding(get:set:)` captures every write the copied body makes; for
    /// `@Query`, `@QueryCore` spares a test from standing up an entire
    /// SwiftData stack just to read an array. (`@Binding` needs no entry: the
    /// verbatim copy of `@Binding var x: T` is already the mockable form — it
    /// IS the mock vehicle. `@FocusState`/`@AccessibilityFocusState` were
    /// once here and got cut: their `.Binding` projections have no public
    /// initializer — a test can't back one with its own closures — and their
    /// writes no-op outside a live view anyway (verified directly), so the
    /// substitution was a pass-through pretending to be a mock; the verbatim
    /// copy behaves identically and needs no knowledge.)
    public var isSubstitutedOnCore: Bool {
        isBindingBackedStorage || isQuery
    }

    /// `@Query` (SwiftData) — the `OutFlow`/`Core` field is always
    /// `QueryCore<WrappedType>`, this package's own drop-in stand-in for the
    /// live wrapper (see `QueryCore.swift` in `Sources/CoreFlow`), carrying
    /// its exact instance surface: `wrappedValue`, `fetchError`, and
    /// `modelContext`, no `projectedValue` — verified directly against the
    /// `_SwiftData_SwiftUI` interface. All three are captured verbatim off the
    /// wrapper instance (the underscore-prefixed backing storage);
    /// `WrappedType` is the property's own declared type (e.g. `[Item]` for
    /// `@Query private var items: [Item]`).
    public var isQuery: Bool {
        wrapperName == "Query"
    }

    /// `@State`/`@AppStorage`/`@SceneStorage` — three wrappers `@Shell`
    /// declares as a real `@Binding var` property (bare wrapped type, not
    /// `Binding<T>`), read via the projected `$` value (not `_`, which gives the
    /// wrapper instance itself — `State<T>`, not `Binding<T>`). All three share
    /// this one case because all three share the same shape, verified directly
    /// against the real SwiftUI interface: `wrappedValue` is `{ get
    /// nonmutating set }` and `projectedValue` genuinely *is* `Binding<T>` for
    /// each of them (verified directly against the real SwiftUI interface —
    /// unlike `@FocusState`, whose projection is its own `.Binding` type with
    /// no public initializer, which is exactly why THAT one isn't
    /// whitelisted). These are the view's own externally
    /// read-*and-write*-able storage — their own storage only installs inside
    /// a live SwiftUI view, so they can't be redeclared as themselves on a
    /// plain struct; `@Binding` is the injectable/settable substitute.
    public var isBindingBackedStorage: Bool {
        wrapperName == "State" || wrapperName == "AppStorage" || wrapperName == "SceneStorage"
    }
}

// MARK: - Collection

/// Collect the stored properties of a struct/class/actor that participate in a
/// generated initializer.
///
/// Skips computed properties, `static`/`class` members, and non-identifier bindings
/// (tuple destructuring). Returns `nil` if a diagnostic was emitted — an init
/// parameter lacking an explicit type (this is syntax-only and can't infer it).
/// `macroName` (e.g. `"Flowable"`) names the attribute in the diagnostic.
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

        // `private(set)`/`fileprivate(set)` land here too — deliberately not
        // special-cased: setter-restricted properties have no place in pure data
        // flow, and the plain-private diagnostic below already rejects them.
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

            let wrapperName = propertyWrapperName(varDecl.attributes)
            let explicitType = binding.typeAnnotation?.type
            let inferredType: TypeSyntax?
            if let explicitType {
                inferredType = explicitType
            } else if wrapperName == "Namespace" {
                // @Namespace has exactly one possible wrapped type —
                // `Namespace.ID` — with no generic parameter to resolve, unlike
                // every other wrapper this macro recognizes (`@State<T>`,
                // `@Query`'s declared element type, …). Unlike those, it needs
                // no explicit annotation at all: the type is inferable from the
                // attribute alone, no type checker required, so a bare
                // `@Namespace private var ns` is filled in here rather than
                // diagnosed as missing a type.
                inferredType = "Namespace.ID"
            } else {
                // Simple syntactic literal inference — `= false` / `= 0` /
                // `= "x"` — matching Swift's own unambiguous default-literal
                // types. Not real type inference (no numeric-literal-defaults-
                // to-Double, no protocol witness resolution): just three literal
                // syntax node kinds this macro can recognize without a type
                // checker, same spirit as the @Namespace case above.
                inferredType = binding.initializer.flatMap { inferredLiteralType($0.value) }
            }

            let property = StoredProperty(
                name: pattern.identifier.text,
                type: inferredType,
                isLet: isLet,
                defaultValue: binding.initializer?.value,
                wrapperName: wrapperName,
                attributeText: varDecl.attributes.isEmpty
                    ? nil : varDecl.attributes.trimmedDescription,
                isPrivate: isPrivate
            )

            // The mapped source-of-truth wrappers — @State/@AppStorage/
            // @SceneStorage/@Query — are
            // a view's own source of truth, never something a caller supplies
            // (that's what @Binding is for), so they must be private.
            // Enforced here, not accommodated later: every renderer
            // downstream can assume the substituted set is always private,
            // with no "what if it's also public" case to reason about or
            // test. Unknown wrappers (and @Environment/@GestureState/… — this
            // macro treats them the same) carry no privacy requirement: their
            // declaration is copied onto Core verbatim either way, and a
            // non-private one simply participates in the generated init like
            // any other non-private field.
            let isSourceOfTruth = property.isSubstitutedOnCore
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

            // A private property with no property wrapper at all is opaque
            // view-owned state that's neither a source of truth nor something a
            // caller supplies — there's no room for it in pure data flow. This
            // used to fall through silently, excluded like a genuine
            // source-of-truth field but with nothing to show for it in
            // OutFlow/Core; now it fails loudly instead.
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

            // Every property that gets this far needs a written type — init
            // parameters obviously, but private wrapper fields too, even the
            // ones excluded from the init: `OutFlow` reads the type to build
            // its tuple field. A wrapper this macro doesn't map
            // (@Environment, @GestureState, @StateObject, a custom one, …) is
            // deliberately NOT refused — it's unknown, and unknowns are
            // copied onto `Core` verbatim (see `renderShell`). `@Namespace`
            // never trips this check — its type is always pre-filled as
            // `Namespace.ID` above, never `nil`.
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

}
