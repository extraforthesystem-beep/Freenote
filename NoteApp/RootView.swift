import SwiftUI

/// Placeholder shell. The library browser replaces this in phase 1.
struct RootView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Label("All Notebooks", systemImage: "books.vertical")
            }
            .navigationTitle("NoteApp")
        } detail: {
            ContentUnavailableView(
                "No notebook open",
                systemImage: "pencil.and.scribble",
                description: Text("The library arrives in phase 1.")
            )
        }
    }
}

#Preview {
    RootView()
}
