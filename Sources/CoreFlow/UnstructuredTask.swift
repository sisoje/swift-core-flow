import SwiftUI

/// What `TaskStorage` needs from its element: any `Task` specialization.
/// Constraining the box on this — instead of on `Task`'s own two generic
/// parameters — means `@UnstructuredTask` only strips the property type's
/// `?` and never parses `Task<Success, Failure>`'s arguments, so a typealias
/// of a task type works (the conformance lives on `Task` itself). Refines
/// `Equatable` — `Task` already is, by identity — so the box can tell a
/// replacement from a self-reassignment.
public protocol CancellableTask: Equatable {
    func cancel()
}

extension Task: CancellableTask {}

/// `@UnstructuredTask`'s storage box, held in a generated `State` field so
/// SwiftUI owns its lifecycle. A class in `State` — not `State<Task?>` —
/// because the lifecycle IS the point: replacing the task cancels the
/// previous one (`willSet`), and the view leaving the graph cancels the live
/// one (`deinit`, a hook a value in `State` doesn't have). The `willSet`
/// is equality-guarded: writing the task it already holds back into the box
/// (a binding round-trip, a defensive `x = x`) must not cancel it —
/// `Task`'s `Equatable` is identity, so a genuinely new task always cancels
/// the old. `@Observable` so a `body` reading the property re-renders when
/// the task changes.
@Observable
public final class TaskStorage<T: CancellableTask> {
    public var task: T? {
        willSet {
            if newValue != task {
                task?.cancel()
            }
        }
    }

    public init(task: T? = nil) {
        self.task = task
    }

    deinit { task?.cancel() }
}

/// A view-owned slot for a cancellable unstructured `Task` — that logs.
/// Assigning a new task cancels the previous one; the live task is cancelled
/// when the view leaves the graph — the two structure guarantees an
/// unstructured `Task { }` doesn't have on its own. And like `@TestState`,
/// every mutation logs `(name, value)` through `\.testLog` at the write
/// site — the value a deterministic `"task"`/`"nil"` (a described `Task` is
/// not snapshot-stable), direct writes and `$name` binding writes alike:
///
/// ```swift
/// struct DownloadButton: View {
///     @UnstructuredTask private var download: Task<Data, Error>?
///
///     var body: some View {
///         Button("Download") {
///             download = Task { … }   // cancels any previous download, logs ("download", "task")
///         }
///     }
/// }
/// ```
///
/// The task always starts `nil` — the property becomes computed over a
/// self-initialized storage peer, and a written default is a compile error
/// thrown by the macro itself; the property is never a memberwise-init
/// parameter, whatever its access level. Required shape: a stored `var`
/// with an optional-sugared type annotation and no initial value
/// (`Task<Success, Failure>?` or a typealias of a task type; `T!` and
/// long-form `Optional<T>` don't count). Anything else is a compile error
/// at the attribute, thrown by the macro — never a silent skip. `$name`
/// and every other generated
/// member is private — only the host's own `body` wires it. Outside a live
/// view, `\.testLog` reads its no-op default — the wrapper is
/// production-safe; logging costs nothing until a sink is installed.
@attached(accessor, names: named(get), named(set))
@attached(peer, names: prefixed(`$`), prefixed(log_), suffixed(_storage))
public macro UnstructuredTask() =
    #externalMacro(module: "CoreFlowMacros", type: "UnstructuredTaskMacro")
