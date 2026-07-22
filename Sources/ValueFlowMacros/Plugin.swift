import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct ValueFlowPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        FlowableMacro.self,
        ShellMacro.self,
        CapabilityMacro.self,
        PickMacro.self,
        RawPropertyMacro.self,
    ]
}
