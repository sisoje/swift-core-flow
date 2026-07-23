import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct CoreFlowPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        FlowableMacro.self,
        ShellMacro.self,
        CapabilityMacro.self,
        PickMacro.self,
        RawPropertyMacro.self,
        TestStateMacro.self,
        TestActionMacro.self,
    ]
}
