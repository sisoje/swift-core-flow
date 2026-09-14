@testable import CoreFlow
import SwiftUI
import XCTest

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

/// Same boundary as `TestStateTests`: seed reads on the generated surface;
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
