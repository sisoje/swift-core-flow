import SwiftUI

// The app-side half of mutation-snapshot testing: UI tests run in a separate
// process, so the filesystem is the shared channel. The test passes a log
// path via SNAPSHOT_LOG; scenarios attach `.loggingMutations(of:)` to the
// Core under test, and every CoreModel history entry is appended as a
// `name = value` line the moment it happens. No SNAPSHOT_LOG (plain tests,
// Cmd-R) → logging is off.

extension URL {
    func append(_ line: String) throws {
        let handle = try FileHandle(forUpdating: self)
        handle.seekToEndOfFile()
        handle.write(Data("\(line)\n".utf8))
        try handle.close()
    }
}

extension View {
    func loggingMutations(of history: [(propertyName: String, value: Any)]) -> some View {
        onChange(of: history.count) { old, new in
            guard new > old,
                let path = ProcessInfo.processInfo.environment["SNAPSHOT_LOG"]
            else { return }
            let url = URL(fileURLWithPath: path)
            for entry in history[old..<new] {
                try! url.append("\(entry.propertyName) = \(entry.value)")
            }
        }
    }
}
