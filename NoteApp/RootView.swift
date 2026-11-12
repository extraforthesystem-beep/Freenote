import SwiftUI

struct RootView: View {
    @State private var model = AppModel()

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView("Opening library…")
            } else if let session = model.session {
                NotebookView(session: session, model: model)
            } else {
                LibraryView(model: model)
            }
        }
        .task { await model.start() }
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
