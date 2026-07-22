import SwiftUI

// The app-side half of mutation-snapshot testing: UI tests run in a separate
// process, so the filesystem is the shared channel. The test passes a log
// path via SNAPSHOT_LOG; the app's `Logger` (see ExampleApp.swift) appends
// each mutation as a `name = value` line THE MOMENT IT HAPPENS — logging
// lives on the binding's own setter, not in some view-layer observer
// replaying what already happened.

extension URL {
    func append(_ line: String) throws {
        let handle = try FileHandle(forUpdating: self)
        handle.seekToEndOfFile()
        handle.write(Data("\(line)\n".utf8))
        try handle.close()
    }
}

@MainActor
extension Binding {
    /// A binding that forwards every write and then calls `perform` with the
    /// new value — mutation logging at the write site, immediately.
    func didSet(_ perform: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: {
                wrappedValue = $0
                perform($0)
            }
        )
    }
}
