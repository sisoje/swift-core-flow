import SwiftUI

// The one example app — one view per file alongside this, and the scene points
// at whichever view is currently being exercised/verified.
@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            DragCard()
        }
    }
}
