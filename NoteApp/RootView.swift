import SwiftUI
#if os(iOS)
import UIKit
#endif

struct RootView: View {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    /// The appearance choice; `nil` follows the device.
    @AppStorage(AppSettings.Key.theme) private var theme: AppTheme = .system
    /// When on, the screen stays lit while the app is open.
    @AppStorage(AppSettings.Key.keepScreenAwake) private var keepScreenAwake = false

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
        #if os(iOS)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepScreenAwake }
        .onChange(of: keepScreenAwake) { _, isOn in
            UIApplication.shared.isIdleTimerDisabled = isOn
        }
        #endif
        .task {
            #if os(iOS)
            MemoryPressure.purgeCachesOnMemoryWarning()
            #endif
            await model.start()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            // Leaving the foreground: the app may be suspended or killed with
            // no further notice, so put every open notebook and pending grade
            // on disk now.
            // Recording stops only in the background: `.inactive` also covers
            // Control Center and the app switcher, which should not end it.
            let sessions = model.tabs
            let study = model.study
            let stopsRecording = phase == .background
            #if os(iOS)
            let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save notebooks")
            #endif
            Task {
                // Grades are a small file; write them first so the last one
                // lands inside the background-task window.
                await study.flushStateWrite()
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
