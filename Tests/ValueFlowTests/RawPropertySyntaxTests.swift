import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import ValueFlowMacros

final class RawPropertySyntaxTests: XCTestCase {
    let macros: [String: Macro.Type] = ["RawProperty": RawPropertyMacro.self]

    func testAnnotationFillsTheWrapperGeneric() {
        assertMacroExpansion(
            """
            struct S {
                @RawProperty @Binding var isOn: Bool
            }
            """,
            expandedSource: """
                struct S {
                    @Binding var isOn: Bool

                    var raw_isOn: Binding<Bool> {
                        get {
                            _isOn
                        }
                        set {
                            _isOn = newValue
                        }
                    }
                }
                """,
            macros: macros
        )
    }

    func testGenericsOnTheAttributeAreUsedVerbatim() {
        assertMacroExpansion(
            """
            struct S {
                @RawProperty @Binding<Bool> var isOn
            }
            """,
            expandedSource: """
                struct S {
                    @Binding<Bool> var isOn

                    var raw_isOn: Binding<Bool> {
                        get {
                            _isOn
                        }
                        set {
                            _isOn = newValue
                        }
                    }
                }
                """,
            macros: macros
        )
    }

    func testDiagnosesUninferrableWrapperType() {
        assertMacroExpansion(
            """
            struct S {
                @RawProperty @Binding var isOn
            }
            """,
            expandedSource: """
                struct S {
                    @Binding var isOn
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "'isOn' needs an explicit type annotation (or generics on the wrapper attribute) so @RawProperty can spell the backing storage's type.",
                    line: 2, column: 5
                )
            ],
            macros: macros
        )
    }

    func testDiagnosesMissingWrapperAttribute() {
        assertMacroExpansion(
            """
            struct S {
                @RawProperty var isOn: Bool = false
            }
            """,
            expandedSource: """
                struct S {
                    var isOn: Bool = false
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "@RawProperty can only be attached to a stored property that also has a property wrapper attribute — there's no backing storage to expose otherwise.",
                    line: 2, column: 5
                )
            ],
            macros: macros
        )
    }
}
