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

    /// `@Bindable` — mirrors verbatim wherever it appears (its `wrappedValue` is a
    /// plain get/set, so the ordinary `self.x = x` assignment path already handles
    /// it with no dedicated rendering logic anywhere downstream). Exists as its own
    /// case only so a private declaration can be named specifically, alongside
    /// `@Binding`/`@ViewBuilder`, as a caller-supplied wrapper that must never be
    /// private.
    public var isBindable: Bool {
        wrapperName == "Bindable"
    }

    /// `@Binding`/`@Bindable`/`@ViewBuilder` — the three wrapper kinds a caller
    /// supplies through the generated init, the opposite of a source-of-truth
    /// wrapper. Declaring one private makes it unreachable (a caller could never
    /// supply it), so it's rejected with its own diagnostic rather than falling
    /// into the generic "wrapper this macro doesn't recognize" message — these
    /// three ARE recognized, just never allowed private.
    public var isCallerSuppliedWrapper: Bool {
        isBinding || isBindable || isViewBuilder
    }

    /// `@Environment` — `@Shell`'s field is a plain `let` of the property's
    /// own declared type, no attribute at all (unlike `@State`/`@AppStorage`,
    /// which keep `@Binding`). Not because the value doesn't change — because
    /// the *attribute* can't be preserved: `@Environment`'s `wrappedValue` has
    /// no public setter (verified directly: `error: cannot assign to property:
    /// 'colorScheme' is a get-only property`), and `@Flowable`'s init always
    /// assigns `self.x = x` — a plain, unattributed `let` has no such
    /// restriction, so the value is captured once, like every other field.
    public var isEnvironment: Bool {
        wrapperName == "Environment"
    }

    /// `@Query` (SwiftData) — the `OutFlow`/`Core` field is always synthesized
    /// as `(wrappedValue: WrappedType, fetchError: Error?)`, built via `#pick`,
    /// regardless of the property's own declared type. `WrappedType` is the
    /// property's own declared type (e.g. `[Item]` for `@Query private var
    /// items: [Item]`); `wrappedValue` and `fetchError` are real members of
    /// SwiftData's `Query` wrapper *instance* (reached via the
    /// underscore-prefixed backing storage), picked verbatim, not synthesized
    /// placeholders — verified directly against the SwiftData interface.
    /// `modelContext` is deliberately left off: plumbing for issuing further
    /// queries/saves, not a snapshot value worth asserting on.
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
    /// each of them — unlike `@FocusState`/`@Namespace` below, which don't.
    /// Unlike `isEnvironment`/`isQuery` above, these are the view's own
    /// externally read-*and-write*-able storage — their own storage only
    /// installs inside a live SwiftUI view, so they can't be redeclared as
    /// themselves on a plain struct; `@Binding` is the injectable/settable
    /// substitute.
    public var isBindingBackedStorage: Bool {
        wrapperName == "State" || wrapperName == "AppStorage" || wrapperName == "SceneStorage"
    }

    /// `@FocusState` — a source-of-truth wrapper alongside
    /// `isBindingBackedStorage`'s three, read the same way (`$x`) but
    /// resolving to a genuinely different projected type: `FocusState<T>.Binding`,
    /// **not** `Binding<T>`. Verified directly against the real SwiftUI interface:
    /// `FocusState<T>.Binding` exposes only `wrappedValue` and
    /// `projectedValue` (itself), no public initializer at all and no
    /// conversion to `Binding<T>` — so it's kept as its own case rather than
    /// folded into `isBindingBackedStorage`, both for the field *type* (`OutFlow`)
    /// and because `@Shell` redeclares it as its own real attribute
    /// (`@FocusState<T>.Binding var x: T`, not `@Binding var x: T`) — see
    /// `outFlowFieldType`/`outFlowFieldReadExpression` (`FlowableRendering.swift`)
    /// and `renderShell` (`ShellRendering.swift`).
    public var isFocusState: Bool {
        wrapperName == "FocusState"
    }

    /// `@Namespace` — treated exactly like `@Environment`: a plain value in
    /// `OutFlow`, a plain unattributed `let` on `Core`. Verified directly
    /// against the real SwiftUI interface: `Namespace.wrappedValue` is
    /// get-only (same "cannot assign to property" error `@Environment` hits),
    /// and unlike `@State`/`@AppStorage`/`@FocusState` it has **no
    /// `projectedValue` at all** — there's no `$x` to fall back on, so it can't
    /// be threaded through as any kind of `Binding`. Its value is stable for the
    /// view instance's lifetime (unlike `@Environment`, which can change if the
    /// environment context above it changes), but the capture works the same
    /// way for both — a one-time plain-value read.
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
                isPrivate: isPrivate
            )

            // @State/@Environment/@Query/@AppStorage/@SceneStorage/@FocusState/
            // @Namespace are each a view's own source of truth — never
            // something a caller supplies (that's what @Binding is for) — so
            // they must be private. Enforced here, not accommodated later:
            // every renderer downstream can assume these seven are always
            // private, with no "what if it's also public" case to reason about
            // or test. @Namespace specifically has no way to thread through a
            // caller-supplied init parameter at all (no `projectedValue`,
            // get-only `wrappedValue` — verified directly), so unlike
            // real-world SwiftUI (where a non-private `@Namespace` is common,
            // e.g. to pass into a child view), this macro requires it private
            // regardless — the same reasoning `@Environment` already sets
            // precedent for.
            let isSourceOfTruth =
                property.isEnvironment || property.isQuery || property.isBindingBackedStorage
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

            // @Binding/@Bindable/@ViewBuilder are the opposite of a
            // source-of-truth wrapper: a caller supplies them through the
            // generated init, so declaring one private makes it unreachable.
            // Checked before the generic "unrecognized wrapper" case below so
            // these three get a message naming the real problem (private,
            // not unrecognized).
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

            // A private property carrying SOME wrapper attribute this package
            // doesn't recognize (@StateObject, @GestureState, a future SwiftUI
            // wrapper, …) is refused outright, rather than silently treated as
            // ordinary opaque private state. Silent fallthrough is exactly how
            // @FocusState went unsupported for a while: it compiled fine, it
            // just quietly never appeared in OutFlow/Core. Forcing a
            // diagnostic here means any future wrapper this macro hasn't been
            // taught about fails loudly instead of compiling into a silent gap.
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
            // @Environment/@Query/@State/@AppStorage/@SceneStorage/@FocusState
            // properties, even though they're excluded from *this* type's own
            // init — @Shell (see ShellRendering.swift) reads
            // their type to build its field (all six eventually get folded
            // into Core's own init, as a plain captured value or a
            // @Binding/@FocusState.Binding substitute). Every other private
            // property — inline-initialized `let` constants, plain private
            // state — is exempt (`private var ole = 0` needs no annotation and
            // doesn't participate in either). `@Namespace` doesn't need this
            // exemption at all — its type is always pre-filled as
            // `Namespace.ID` above, never `nil`, so this check never even sees
            // a missing type to diagnose for it.
            let needsType =
                !property.isPrivate || property.isEnvironment || property.isQuery
                || property.isBindingBackedStorage || property.isFocusState
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
                "'\(propertyName)' must be private — @State/@Environment/@Query/@AppStorage/@SceneStorage/@FocusState/@Namespace are a view's own source of truth, not something a caller supplies (use @Binding for that).",
            id: "sourceOfTruthMustBePrivate"
        )
    }

    public static func plainPrivatePropertyNotAllowed(macroName: String, propertyName: String)
        -> DataTypeMacroDiagnostic
    {
        DataTypeMacroDiagnostic(
            message:
                "'\(propertyName)' is private with no property wrapper — @\(macroName) has no room for opaque private state in pure data flow. Make it non-private, or give it a recognized source-of-truth wrapper (@State/@Environment/@Query/@AppStorage/@SceneStorage/@FocusState/@Namespace).",
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

    public static func unsupportedPrivateWrapper(
        macroName: String, propertyName: String, wrapperName: String
    )
        -> DataTypeMacroDiagnostic
    {
        DataTypeMacroDiagnostic(
            message:
                "'\(propertyName)' uses @\(wrapperName), a private property wrapper @\(macroName) doesn't recognize — it would be silently excluded from OutFlow/Core instead of captured like @Environment/@Query/@State/@AppStorage/@SceneStorage/@FocusState/@Namespace. Make '\(propertyName)' non-private, remove @\(wrapperName), or extend this macro's support for it.",
            id: "unsupportedPrivateWrapper"
        )
    }
}
