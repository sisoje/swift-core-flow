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
