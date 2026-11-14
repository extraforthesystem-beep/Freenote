#if os(iOS)
import TipKit
#endif
import SwiftUI

@main
struct NoteAppApp: App {
    /// One model for the window and, on the Mac, the Settings window: Settings
    /// must edit the library that is open, not a second copy of it.
    @State private var model = AppModel()

    init() {
        #if os(iOS)
        // The editor's one-time undo hint is a TipKit tip; without a datastore
        // TipKit has nowhere to remember that it has already been shown.
        try? Tips.configure([.displayFrequency(.immediate)])
        #endif
    }

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
