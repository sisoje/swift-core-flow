import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// A query service's initializer and its default value. Every stored property
/// of the service is a query: a function answering `LazyQuery`, taken by the
/// initializer as its query expression and made lazy by `QueryUtilities.lazy`.
/// Entry point, the one type rule and the renderer, all in this file.
public enum LazyQueriesMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard
            let (properties, access) = validatedProperties(
                of: declaration, attachedTo: node, macroName: "LazyQueries", in: context
            )
        else {
            return []
        }
        let stored = properties.filter { !$0.isPrivate }
        let queries = stored.compactMap(LazyQueryMember.init)
        // A member the service cannot take as a query has no place in it:
        // diagnosed, never left out of the initializer.
        guard queries.count == stored.count else {
            for property in stored where LazyQueryMember(property) == nil {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(property.binding),
                        message: DataTypeMacroDiagnostic.notALazyQuery(propertyName: property.name)
                    )
                )
            }
            return []
        }
        return renderLazyQueries(queries, access: access)
    }
}

/// One query of the service, read off its member's type.
struct LazyQueryMember {
    let name: String
    /// The member's own function type, argument labels and all, with its
    /// result renamed `Query`: what the initializer takes.
    let expressionType: String
    let argumentCount: Int
    /// `Query()` exists where the result is an array. A sectioned query has
    /// to name its section, so it has no default.
    let answersArray: Bool

    /// Nil unless the type is a function type with no attributes whose result
    /// is spelled `LazyQuery<…>`. An attributed one (`@MainActor`,
    /// `@Sendable`) is refused because the lifted line could not compile:
    /// what `QueryUtilities.lazy` returns is a plain function and does not
    /// convert to one (`converting non-Sendable function value to '@MainActor
    /// @Sendable …' may introduce data races`). A qualified or aliased result
    /// is not seen, the package's syntax-only rule.
    init?(_ property: StoredProperty) {
        guard let function = property.type?.as(FunctionTypeSyntax.self),
              let result = function.returnClause.type.as(IdentifierTypeSyntax.self),
              result.name.text == "LazyQuery"
        else {
            return nil
        }
        let query = result.with(\.name, result.name.with(\.tokenKind, .identifier("Query")))
        name = property.name
        expressionType = function.with(\.returnClause.type, TypeSyntax(query)).trimmedDescription
        argumentCount = function.parameters.count
        // The generic argument's own node, whatever swift-syntax calls it:
        // its first child is the type as written.
        answersArray =
            result.genericArgumentClause?.arguments.last?
                .children(viewMode: .sourceAccurate).first?.is(ArrayTypeSyntax.self) ?? false
    }

    /// The default query, whatever the member is asked with: every element,
    /// unsorted.
    var defaultExpression: String {
        argumentCount == 0
            ? "{ Query() }"
            : "{ \(Array(repeating: "_", count: argumentCount).joined(separator: ", ")) in Query() }"
    }
}

/// The initializer, and `defaultQueries` when every query answers an array.
/// One query per line, unlike `renderFlowable`: a query expression's type is
/// long and a service holds several. A parameter carries no default,
/// whatever the member has: the member's default is a function answering
/// `LazyQuery`, not the query expression the parameter takes.
///
/// `defaultQueries` is `@MainActor` because its closures build a `Query`,
/// whose initializers are. The attribute is written out so the expansion
/// compiles in a module with no default isolation too.
func renderLazyQueries(_ queries: [LazyQueryMember], access: String) -> [DeclSyntax] {
    func list(_ indentation: String, _ line: (LazyQueryMember) -> String) -> String {
        queries.isEmpty
            ? ""
            : "\n" + queries.map { indentation + "    " + line($0) }.joined(separator: ",\n") + "\n" + indentation
    }

    var decls = [
        DeclSyntax(
            stringLiteral: """
            \(access)init(\(list("") { "\($0.name): @escaping \($0.expressionType)" })) {
            \(queries.map { "    self.\($0.name) = QueryUtilities.lazy(\($0.name))" }.joined(separator: "\n"))
            }
            """
        ),
    ]
    if queries.allSatisfy(\.answersArray) {
        decls.append(
            DeclSyntax(
                stringLiteral: """
                @MainActor \(access)static var defaultQueries: Self {
                    Self(\(list("    ") { "\($0.name): \($0.defaultExpression)" }))
                }
                """
            )
        )
    }
    return decls
}
