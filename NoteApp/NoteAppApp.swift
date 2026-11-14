import SwiftUI

@main
struct NoteAppApp: App {
    /// One model for the window and, on the Mac, the Settings window: Settings
    /// must edit the library that is open, not a second copy of it.
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        #if os(macOS)
        // Gives the standard ⌘, a Settings window on the Mac.
        Settings {
            SettingsView(model: model)
                .task { await model.start() }
        }
        #endif
    }
}
