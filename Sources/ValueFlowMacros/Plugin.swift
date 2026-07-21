import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct ValueFlowPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        DataLayoutMacro.self,
        ShellMacro.self,
        CapabilityMacro.self,
        PickMacro.self,
    ]
}
