import SwiftUI

@main
struct ModoApp: App {
    // AppDelegate owns the NSStatusItem and floating window. We use the
    // adaptor so SwiftUI's lifecycle still boots the app, but there is no
    // main WindowGroup — this is a menu bar (LSUIElement) accessory app.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
