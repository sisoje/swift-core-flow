import SwiftSyntax
import SwiftSyntaxMacros

enum ShellHostKind {
    case view
    case viewModifier
    case none
}

/// Textual, not semantic — macros never get a type checker (verified against
/// the pinned swift-syntax 603.0.2: `expansion` receives only syntax +
/// context). Misses conformance declared in a separate extension, via a
/// typealias or composition, or spelled qualified (`SwiftUI.View`) — only a
/// bare identifier in the attached type's own inheritance clause counts.
func detectHostKind(of declaration: some DeclGroupSyntax) -> ShellHostKind {
    let inherited =
        declaration.inheritanceClause?.inheritedTypes.compactMap {
            $0.type.as(IdentifierTypeSyntax.self)?.name.text
        } ?? []
    if inherited.contains("ViewModifier") { return .viewModifier }
    if inherited.contains("View") { return .view }
    return .none
}

/// Every non-stored, non-init member's source text, dedented, for
/// `renderShell` to copy into `Core`. Stored properties become `Core`'s own
/// fields; a copied init would suppress the synthesized memberwise init —
/// the only way tests construct a `Core`. The copy is legal because it
/// happens inside `@Shell`'s *own* expansion: only names from a *different*
/// expansion are unreferenceable (verified directly, five ways), which is
/// why no freestanding `#CoreBody`-style design can do this. Copies compile
/// against `Core`'s fields by read-surface parity — `$x` is `Binding<T>` on
/// both sides, `@Query`'s fetched value reads directly on both, and a
/// verbatim copy *is* the same declaration. Members in a separate extension
/// aren't seen (syntax-only, like `detectHostKind`).
func copiedMemberSources(of declaration: some DeclGroupSyntax) -> [String] {
    declaration.memberBlock.members.compactMap { member in
        if member.decl.is(InitializerDeclSyntax.self) { return nil }
        if let varDecl = member.decl.as(VariableDeclSyntax.self) {
            let isStatic = varDecl.modifiers.contains {
                $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
            }
            // Stored instance properties (observer-only accessors included)
            // are Core's substituted fields, not copies. Static stored
            // properties ARE copied — a body referencing `constant` unqualified
            // needs Core to carry its own.
            let isStored = varDecl.bindings.allSatisfy { binding in
                binding.accessorBlock.map { !isComputed($0) } ?? true
            }
            if !isStatic && isStored { return nil }
        }
        return dedented(member.decl.trimmedDescription)
    }
}

/// `trimmedDescription` keeps inner lines at their source columns, and the
/// expansion machinery re-shifts every line by the splice position — without
/// dedenting to column 0 first, copies land double-indented.
private func dedented(_ source: String) -> String {
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard lines.count > 1 else { return source }
    let indents = lines.dropFirst()
        .filter { !$0.allSatisfy(\.isWhitespace) }
        .map { $0.prefix(while: { $0 == " " }).count }
    guard let minIndent = indents.min(), minIndent > 0 else { return source }
    return
        ([lines[0]]
        + lines.dropFirst().map { line in
            String(line.dropFirst(min(minIndent, line.prefix(while: { $0 == " " }).count)))
        })
        .joined(separator: "\n")
}

/// Entry point only — `renderShell` (`ShellRendering.swift`) documents the
/// rules. Independent of `@Flowable`: collects the stored properties itself
/// via the shared `validatedProperties`.
public enum ShellMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard
            // The type's own access level is deliberately unused here — Core
            // and every generated field are always internal (or private,
            // for verbatim-copied private wrappers).
            let (properties, _) = validatedProperties(
                of: declaration, attachedTo: node, macroName: "Shell", in: context
            )
        else {
            return []
        }
        return renderShell(
            properties: properties, hostKind: detectHostKind(of: declaration),
            copiedMembers: copiedMemberSources(of: declaration))
    }
}
