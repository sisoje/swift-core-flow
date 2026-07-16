import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct DataMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MemberwiseInitMacro.self,
        DataLayoutInitMacro.self,
        PickMacro.self,
    ]
}
