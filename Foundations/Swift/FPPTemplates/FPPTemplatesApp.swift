import SwiftUI

@main
struct FPPTemplatesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
    }
}
