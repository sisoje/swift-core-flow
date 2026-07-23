import Foundation

// The app-side half of mutation-snapshot testing: UI tests run in a separate
// process, so the filesystem is the shared channel. The test passes a log
// path via SNAPSHOT_LOG; the app's `testLog` sink (see ExampleApp.swift)
// appends each mutation as a `name = value` line THE MOMENT IT HAPPENS —
// logging lives on the @TestHost-generated setters/wrappers, not in some
// view-layer observer replaying what already happened.

extension URL {
    func append(_ line: String) throws {
        let handle = try FileHandle(forUpdating: self)
        handle.seekToEndOfFile()
        handle.write(Data("\(line)\n".utf8))
        try handle.close()
    }
}
