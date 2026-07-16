import SwiftSyntax

/// Render the `DataLayout` typealias + init for `properties`, at the given access
/// level. One property → `DataLayout` aliases its bare type directly (Swift has no
/// 1-tuples: `(x: T)` as a type collapses to plain `T`, no `.x` accessor), and the
/// init parameter uses the property's own name *and* type directly rather than
/// routing through the alias — `DataLayout` is declared for API uniformity (every
/// `@DataLayoutInit` type has one), but this init doesn't need it: spelling out `T`
/// costs nothing here, unlike the tuple case below. Two or more properties →
/// `DataLayout` aliases a tuple of them, and the init takes it as one `dataLayout:
/// DataLayout` parameter — routing through the alias there actually saves spelling
/// out the whole tuple type inline. Zero properties yields a plain empty init.
///
/// Unlike `@MemberwiseInit`'s per-parameter rendering, no per-field default can be
/// attached here — tuple element types don't support `= default` — so inline `var`
/// defaults and optional-implies-`nil` are both dropped; every field is required at
/// the call site. A function-typed field also never gets `@escaping` (see
/// `baseTypeText`): that attribute is only legal directly on a function *parameter*,
/// and here the parameter is `DataLayout` as a whole — a closure nested inside it is
/// already escaping. `@ViewBuilder` is passed `wrapViewBuilder: false` below — a
/// stored-value field (`@ViewBuilder let footer: Content`) keeps its own type
/// (`Content`) and is assigned directly, *not* turned into a `() -> Content` builder:
/// there's no parameter position inside a tuple literal for the trailing-closure
/// sugar that wrapping exists to enable, and a closure would make `DataLayout` — data
/// meant to be passed around/stored/diffed — hold something that isn't `Equatable`
/// or comparable for no benefit.
public func renderDataLayoutMembers(properties: [StoredProperty], access: String) -> [DeclSyntax] {
    let initParams = properties.filter { !$0.isPrivate }
    guard !initParams.isEmpty else {
        return [DeclSyntax(stringLiteral: "\(access)init() {}")]
    }

    let isTuple = initParams.count > 1
    let rhs =
        isTuple
        ? "(" + initParams.map { "\($0.name): \(baseTypeText($0, wrapViewBuilder: false))" }
            .joined(separator: ", ") + ")"
        : baseTypeText(initParams[0], wrapViewBuilder: false)
    let paramName = isTuple ? "dataLayout" : initParams[0].name
    // Routing through `DataLayout` saves spelling out the tuple inline; for a lone
    // property there's nothing to save, so the init just uses its own type.
    let paramType = isTuple ? "DataLayout" : rhs

    let assignments =
        initParams
        .map {
            fieldAssignment(
                $0, source: isTuple ? "\(paramName).\($0.name)" : paramName, wrapViewBuilder: false
            )
        }
        .joined(separator: "\n")

    return [
        DeclSyntax(stringLiteral: "\(access)typealias DataLayout = \(rhs)"),
        DeclSyntax(
            stringLiteral: """
                \(access)init(_ \(paramName): \(paramType)) {
                \(assignments)
                }
                """
        ),
    ]
}
