@testable import CoreFlow
import SwiftUI
import XCTest

/// The lifecycle lives in `TaskStorage`, so it's tested there directly —
/// no view, no macro. Ported from the standalone TaskState package.
final class TaskStorageTests: XCTestCase {
    func testReplacingTaskCancelsPreviousAndSparesTheReplacement() async {
        let storage = TaskStorage<Task<Void, Never>>()

        let started = expectation(description: "started")
        let first = Task {
            started.fulfill()
            while !Task.isCancelled {
                await Task.yield()
            }
        }
        storage.task = first
        await fulfillment(of: [started], timeout: 1)

        let secondStarted = expectation(description: "second started")
        let second = Task {
            secondStarted.fulfill()
            while !Task.isCancelled {
                await Task.yield()
            }
        }
        storage.task = second // replacing must cancel the previous — willSet
        await first.value
        XCTAssertTrue(first.isCancelled)

        await fulfillment(of: [secondStarted], timeout: 1)
        XCTAssertFalse(second.isCancelled, "the replacement must survive its own arrival")

        storage.task = nil // nil is a genuine replacement — cancels
        await second.value
        XCTAssertTrue(second.isCancelled)
    }

    /// The willSet is equality-guarded (Task's Equatable is identity):
    /// writing the task the box already holds back into it — a binding
    /// round-trip, a defensive `x = x` — must not cancel it.
    func testReassigningTheSameTaskDoesNotCancelIt() async {
        let storage = TaskStorage<Task<Void, Never>>()

        let started = expectation(description: "started")
        let task = Task {
            started.fulfill()
            while !Task.isCancelled {
                await Task.yield()
            }
        }
        storage.task = task
        await fulfillment(of: [started], timeout: 1)

        storage.task = storage.task // self-reassignment — not a replacement
        XCTAssertFalse(task.isCancelled) // cancellation is synchronous in willSet

        storage.task = nil
        await task.value
        XCTAssertTrue(task.isCancelled)
    }

    func testDeinitCancelsTask() async {
        let started = expectation(description: "started")
        let task = Task {
            started.fulfill()
            while !Task.isCancelled {
                await Task.yield()
            }
        }

        var storage: TaskStorage<Task<Void, Never>>? = TaskStorage()
        storage?.task = task
        await fulfillment(of: [started], timeout: 1)

        storage = nil // deinit → cancellation (State teardown, in a view)
        _ = storage

        await task.value
        XCTAssertTrue(task.isCancelled)
    }
}

/// Compiles only if `@UnstructuredTask` expands and type-checks inside a real
/// View — get, set, and the private `$` binding, wired by the host's own body.
private struct DemoView: View {
    @UnstructuredTask var download: Task<Void, Never>?

    var body: some View {
        Button("Go") {
            download = Task {} // set — cancels previous, logs ("download", "task")
            let _: Task<Void, Never>? = download // get
            let _: Binding<Task<Void, Never>?> = $download // projection
        }
    }
}

/// Under `@Shell` the wrapper rides rule 2 — the verbatim copy re-expands
/// the macro on `Core`, and the computed property is never a memberwise-init
/// parameter, so `Core()` constructs bare.
@Shell
private struct ShellHost: View {
    @UnstructuredTask private var work: Task<Void, Never>?

    var body: some View {
        Color.clear
    }
}

/// Same boundary as `TestSupportTests`: seed reads on the generated surface;
/// mutation logging is exercised where a live render installs the sink.
@MainActor
final class UnstructuredTaskTests: XCTestCase {
    func testBareConstructionAndSeedRead() {
        let view = DemoView()
        XCTAssertNil(view.download)
    }

    func testShellCoreReExpandsTheMacroAndConstructsBare() {
        _ = ShellHost.Core()
        _ = ShellHost() // the host takes no parameters either — never a memberwise param
    }
}
