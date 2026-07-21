import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct ValueFlowPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        DataLayoutMacro.self,
        StatelessNodeMacro.self,
        CapabilityMacro.self,
        PickMacro.self,
    ]
}
