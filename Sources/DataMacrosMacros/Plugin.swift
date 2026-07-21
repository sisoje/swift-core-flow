import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct DataMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        DataLayoutMacro.self,
        StatelessNodeMacro.self,
        CapabilityMacro.self,
        PickMacro.self,
    ]
}
