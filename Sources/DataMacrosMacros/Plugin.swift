import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct DataMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MemberwiseInitMacro.self,
        CapabilityMacro.self,
        PickMacro.self,
    ]
}
