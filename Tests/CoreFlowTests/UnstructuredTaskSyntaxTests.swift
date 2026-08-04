import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import CoreFlowMacros

final class UnstructuredTaskSyntaxTests: XCTestCase {
    let macros: [String: Macro.Type] = [
        "UnstructuredTask": UnstructuredTaskMacro.self
    ]

    func testExpansion() {
        assertMacroExpansion(
            """
            struct Host {
                @UnstructuredTask private var download: Task<Data, Error>?
            }
            """,
            expandedSource: """
                struct Host {
                    private var download: Task<Data, Error>? {
                        get {
                            download_storage.wrappedValue.task
                        }
                        nonmutating set {
                            log_download.wrappedValue("download", newValue == nil ? "nil" : "task")
                            download_storage.wrappedValue.task = newValue
                        }
                    }

                    private let download_storage: State<TaskStorage<Task<Data, Error>>> = State(wrappedValue: TaskStorage())

                    private let log_download = TestLog()

                    private var `$download`: Binding<Task<Data, Error>?> {
                        Binding(
                            get: {
                                self.download
                            },
                            set: {
                                self.download = $0
                            }
                        )
                    }
                }
                """,
            macros: macros
        )
    }

    // A typealias of a task type expands identically — the storage element is
    // the annotation minus its `?`, never a parsed `Task<Success, Failure>`.
    func testTypealiasedTaskType() {
        assertMacroExpansion(
            """
            struct Host {
                @UnstructuredTask var work: VoidTask?
            }
            """,
            expandedSource: """
                struct Host {
                    var work: VoidTask? {
                        get {
                            work_storage.wrappedValue.task
                        }
                        nonmutating set {
                            log_work.wrappedValue("work", newValue == nil ? "nil" : "task")
                            work_storage.wrappedValue.task = newValue
                        }
                    }

                    private let work_storage: State<TaskStorage<VoidTask>> = State(wrappedValue: TaskStorage())

                    private let log_work = TestLog()

                    private var `$work`: Binding<VoidTask?> {
                        Binding(
                            get: {
                                self.work
                            },
                            set: {
                                self.work = $0
                            }
                        )
                    }
                }
                """,
            macros: macros
        )
    }

}
