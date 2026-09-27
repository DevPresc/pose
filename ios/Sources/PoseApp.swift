import SwiftUI

@main
struct PoseApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .statusBar(hidden: true)
                .persistentSystemOverlays(.hidden)
        }
    }
}
