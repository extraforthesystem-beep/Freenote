import SwiftUI
#if os(iOS)
import UIKit
#endif

struct RootView: View {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    /// The appearance choice; `nil` follows the device.
    @AppStorage(AppSettings.Key.theme) private var theme: AppTheme = .system

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView("Opening library…")
            } else if model.isShowingLibrary || model.session == nil {
                LibraryView(model: model)
            } else {
                NotebookView(model: model)
            }
        }
        .preferredColorScheme(theme.colorScheme)
        .task {
            #if os(iOS)
            MemoryPressure.purgeCachesOnMemoryWarning()
            #endif
            await model.start()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            // Leaving the foreground: the app may be suspended or killed with
            // no further notice, so put every open notebook on disk now.
            // Recording stops only in the background: `.inactive` also covers
            // Control Center and the app switcher, which should not end it.
            let sessions = model.tabs
            let stopsRecording = phase == .background
            #if os(iOS)
            let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save notebooks")
            #endif
            Task {
                for session in sessions {
                    if stopsRecording {
                        await session.audio.stopRecording()
                    }
                    await session.flushPendingSave()
                }
                #if os(iOS)
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                }
                #endif
            }
        }
        .alert(
            model.notice?.title ?? "Something went wrong",
            isPresented: Binding(
                get: { model.notice != nil },
                set: { if !$0 { model.notice = nil } }
            ),
            presenting: model.notice
        ) { _ in
            Button("OK", role: .cancel) { model.notice = nil }
        } message: { notice in
            Text(notice.message)
        }
    }
}

#Preview {
    RootView()
}
