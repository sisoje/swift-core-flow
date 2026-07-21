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

    /// `@FocusState` — a fourth source-of-truth wrapper, alongside `@State`/
    /// `@AppStorage`, read the same way (`self.$x`) but resolving to a
    /// genuinely different projected type: `FocusState<T>.Binding`, **not**
    /// `Binding<T>`. Verified directly against the real SwiftUI interface:
    /// `FocusState<T>.Binding` exposes only `wrappedValue` and
    /// `projectedValue` (itself), no public initializer at all and no
    /// conversion to `Binding<T>` — so it's kept as its own case rather than
    /// folded into `isStateOrAppStorage`, both for the field *type* (`OutFlow`)
    /// and because `@StatelessNode` redeclares it as its own real attribute
    /// (`@FocusState<T>.Binding var x: T`, not `@Binding var x: T`) — see
    /// `outFlowFieldType`/`outFlowFieldReadExpression` (`DataLayoutRendering.swift`)
    /// and `renderStatelessNode` (`StatelessNodeRendering.swift`).
    public var isFocusState: Bool {
        wrapperName == "FocusState"
    }

    /// `@Namespace` — treated exactly like `@Environment`: a plain, unattributed
    /// `let` on `StatelessNode`, excluded from `OutFlow` entirely. Verified
    /// directly against the real SwiftUI interface: `Namespace.wrappedValue` is
    /// get-only (same "cannot assign to property" error `@Environment` hits),
    /// and unlike `@State`/`@AppStorage`/`@FocusState` it has **no
    /// `projectedValue` at all** — there's no `$x` to fall back on, so it can't
    /// be threaded through as any kind of `Binding`. Its value is stable for the
    /// view instance's lifetime (unlike `@Environment`, which can change if the
    /// environment context above it changes), but it's grouped with
    /// `@Environment` anyway rather than added to `OutFlow`: nothing currently
    /// demonstrates a need for it there, and `StatelessNode`'s plain-`let`
    /// capture already covers the same "assert on it with no live view" use case
    /// `OutFlow` exists for.
    public var isNamespace: Bool {
        wrapperName == "Namespace"
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

            let wrapperName = propertyWrapperName(varDecl.attributes)
            // @Namespace has exactly one possible wrapped type — `Namespace.ID`
            // — with no generic parameter to resolve, unlike every other
            // wrapper this macro recognizes (`@State<T>`, `@Query`'s declared
            // element type, …). Unlike those, it needs no explicit annotation
            // at all: the type is inferable from the attribute alone, no type
            // checker required, so a bare `@Namespace private var ns` is filled
            // in here rather than diagnosed as missing a type.
            let explicitType = binding.typeAnnotation?.type
            let inferredType: TypeSyntax? =
                wrapperName == "Namespace" ? (explicitType ?? "Namespace.ID") : explicitType

            let property = StoredProperty(
                name: pattern.identifier.text,
                type: inferredType,
                isLet: isLet,
                defaultValue: binding.initializer?.value,
                wrapperName: wrapperName,
                isPrivate: isPrivate
            )

            // @State/@Environment/@Query/@AppStorage/@FocusState/@Namespace are
            // each a view's own source of truth — never something a caller
            // supplies (that's what @Binding is for) — so they must be private.
            // Enforced here, not accommodated later: every renderer downstream
            // can assume these six are always private, with no "what if it's
            // also public" case to reason about or test. @Namespace specifically
            // has no way to thread through a caller-supplied init parameter at
            // all (no `projectedValue`, get-only `wrappedValue` — verified
            // directly), so unlike real-world SwiftUI (where a non-private
            // `@Namespace` is common, e.g. to pass into a child view), this
            // macro requires it private regardless — the same reasoning
            // `@Environment` already sets precedent for.
            let isSourceOfTruth =
                property.isEnvironment || property.isQuery || property.isStateOrAppStorage
                || property.isFocusState || property.isNamespace
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

            // A private property carrying SOME wrapper attribute this package
            // doesn't recognize (@StateObject, @GestureState, @SceneStorage, a
            // private @Binding/@ViewBuilder/@Bindable, a future SwiftUI wrapper,
            // …) is refused outright, rather than silently treated as ordinary
            // opaque private state — the same fallthrough `private var cache = 0`
            // gets. Silent fallthrough is exactly how @FocusState went
            // unsupported for a while: it compiled fine, it just quietly never
            // appeared in OutFlow/StatelessNode. Forcing a diagnostic here means
            // any future wrapper this macro hasn't been taught about fails loudly
            // instead of compiling into a silent gap.
            if property.isPrivate, let wrapperName = property.wrapperName, !isSourceOfTruth {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(binding),
                        message: DataTypeMacroDiagnostic.unsupportedPrivateWrapper(
                            macroName: macroName, propertyName: property.name,
                            wrapperName: wrapperName
                        )
                    )
                )
                hadError = true
                continue
            }

            // Init parameters need a written type; so do
            // @Environment/@Query/@State/@AppStorage/@FocusState properties,
            // even though they're excluded from *this* type's own init —
            // @StatelessNode (see StatelessNodeRendering.swift) reads their
            // type to build its field (all five eventually get folded into
            // StatelessNode's own init, as a plain captured value or a
            // @Binding/@FocusState.Binding substitute). Every other private
            // property — inline-initialized `let` constants, plain private
            // state — is exempt (`private var ole = 0` needs no annotation and
            // doesn't participate in either). `@Namespace` doesn't need this
            // exemption at all — its type is always pre-filled as
            // `Namespace.ID` above, never `nil`, so this check never even sees
            // a missing type to diagnose for it.
            let needsType =
                !property.isPrivate || property.isEnvironment || property.isQuery
                || property.isStateOrAppStorage || property.isFocusState
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
                "'\(propertyName)' must be private — @State/@Environment/@Query/@AppStorage/@FocusState/@Namespace are a view's own source of truth, not something a caller supplies (use @Binding for that).",
            id: "sourceOfTruthMustBePrivate"
        )
    }

    public static func unsupportedPrivateWrapper(
        macroName: String, propertyName: String, wrapperName: String
    )
        -> DataTypeMacroDiagnostic
    {
        DataTypeMacroDiagnostic(
            message:
                "'\(propertyName)' uses @\(wrapperName), a private property wrapper @\(macroName) doesn't recognize — it would be silently excluded from OutFlow/StatelessNode instead of captured like @Environment/@Query/@State/@AppStorage/@FocusState/@Namespace. Make '\(propertyName)' non-private, remove @\(wrapperName), or extend this macro's support for it.",
            id: "unsupportedPrivateWrapper"
        )
    }
}
