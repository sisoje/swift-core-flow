import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - Macro

/// Adds a `Capability` typealias + `capability` computed property bundling every
/// eligible computed property/method of the declaration it's attached to. See the
/// doc comment on `@Capability` (in `Sources/DataMacros/Capability.swift`) for the
/// full picture. Unlike the stored-property macros, this reads a struct/class/actor
/// OR an extension of one — it only needs to see whatever's written in that one
/// declaration, which an extension can supply just as well as a primary type body.
public enum CapabilityMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard
            declaration.is(StructDeclSyntax.self) || declaration.is(ClassDeclSyntax.self)
                || declaration.is(ActorDeclSyntax.self) || declaration.is(ExtensionDeclSyntax.self)
        else {
            context.diagnose(
                Diagnostic(node: node, message: CapabilityDiagnostic.notAnEligibleDeclaration)
            )
            return []
        }
        guard let members = collectCapabilityMembers(of: declaration, in: context) else {
            return []
        }
        let access = accessLevel(of: declaration)
        return renderCapabilityMembers(members: members, access: access)
    }
}

// MARK: - Member model

/// One computed property or method that participates in `Capability` — its output
/// label and the type its tuple field gets.
struct CapabilityMember {
    let name: String
    let typeText: String
}

// MARK: - Collection

/// Collect the computed properties and instance methods of `decl` that participate
/// in `Capability`. Returns `nil` if a diagnostic was emitted — a computed property
/// missing its required type annotation, or nothing eligible found at all.
func collectCapabilityMembers(
    of decl: some DeclGroupSyntax,
    in context: some MacroExpansionContext
) -> [CapabilityMember]? {
    var members: [CapabilityMember] = []
    var hadError = false

    for member in decl.memberBlock.members {
        if let varDecl = member.decl.as(VariableDeclSyntax.self) {
            guard !isExcluded(varDecl.modifiers) else { continue }

            for binding in varDecl.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                // Only computed properties participate — a stored property (no
                // accessor block, or one with only willSet/didSet) is skipped.
                guard let accessorBlock = binding.accessorBlock, isComputed(accessorBlock) else {
                    continue
                }

                guard let type = binding.typeAnnotation?.type else {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(binding),
                            message: CapabilityDiagnostic.missingType(pattern.identifier.text)
                        )
                    )
                    hadError = true
                    continue
                }

                members.append(
                    CapabilityMember(name: pattern.identifier.text, typeText: type.trimmedDescription)
                )
            }
        } else if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
            guard !isExcluded(funcDecl.modifiers) else { continue }
            // A mutating method can't be referenced as a plain closure value on a
            // struct/enum (`self` isn't mutable in that expression) — Swift rejects
            // it outright, so there's no useful field to generate here.
            let isMutating = funcDecl.modifiers.contains { $0.name.tokenKind == .keyword(.mutating) }
            guard !isMutating else { continue }

            let params =
                funcDecl.signature.parameterClause.parameters
                .map { $0.type.trimmedDescription }
                .joined(separator: ", ")
            var effects = ""
            if funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil { effects += " async" }
            if funcDecl.signature.effectSpecifiers?.throwsClause != nil { effects += " throws" }
            let returnType = funcDecl.signature.returnClause?.type.trimmedDescription ?? "Void"

            members.append(
                CapabilityMember(
                    name: funcDecl.name.text,
                    typeText: "(\(params))\(effects) -> \(returnType)"
                )
            )
        }
    }

    guard !hadError else { return nil }
    guard !members.isEmpty else {
        context.diagnose(Diagnostic(node: Syntax(decl), message: CapabilityDiagnostic.noEligibleMembers))
        return nil
    }
    return members
}

/// True for `private`/`fileprivate` (implementation detail) or `static`/`class`
/// (not instance behavior) — excluded from `Capability` either way.
private func isExcluded(_ modifiers: DeclModifierListSyntax) -> Bool {
    modifiers.contains {
        $0.name.tokenKind == .keyword(.private) || $0.name.tokenKind == .keyword(.fileprivate)
            || $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
    }
}

// MARK: - Rendering

/// Render the `Capability` typealias + `capability` computed property for `members`,
/// at the given access level. Two or more members get a tuple `Capability`; exactly
/// one collapses to that member's bare type/value (Swift has no 1-tuples, same
/// collapse `@DataLayoutInit` does).
func renderCapabilityMembers(members: [CapabilityMember], access: String) -> [DeclSyntax] {
    let isTuple = members.count > 1

    let rhs =
        isTuple
        ? "(" + members.map { "\($0.name): \($0.typeText)" }.joined(separator: ", ") + ")"
        : members[0].typeText

    let body =
        isTuple
        ? "    (" + members.map(\.name).joined(separator: ", ") + ")"
        : "    \(members[0].name)"

    return [
        DeclSyntax(stringLiteral: "\(access)typealias Capability = \(rhs)"),
        DeclSyntax(
            stringLiteral: """
                \(access)var capability: Capability {
                \(body)
                }
                """
        ),
    ]
}

// MARK: - Diagnostics

struct CapabilityDiagnostic: DiagnosticMessage {
    let message: String
    let id: String
    var severity: DiagnosticSeverity { .error }

    var diagnosticID: MessageID {
        MessageID(domain: "DataMacros", id: id)
    }

    static let notAnEligibleDeclaration = CapabilityDiagnostic(
        message: "@Capability can only be attached to a struct, class, actor, or an extension of one.",
        id: "notAnEligibleDeclaration"
    )

    static func missingType(_ name: String) -> CapabilityDiagnostic {
        CapabilityDiagnostic(
            message:
                "Computed property '\(name)' needs an explicit type annotation so @Capability can include it.",
            id: "missingType"
        )
    }

    static let noEligibleMembers = CapabilityDiagnostic(
        message:
            "@Capability found no eligible computed properties or methods — nothing to bundle into a Capability.",
        id: "noEligibleMembers"
    )
}
