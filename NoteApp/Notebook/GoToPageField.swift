import SwiftUI

/// A one-line "Go to Page" row for a popover or a List. Typing a page number
/// and pressing Return jumps there; the iPad number pad has no Return key, so
/// the keyboard also carries a Go button. The field shows the valid range.
struct GoToPageField: View {
    let pageCount: Int
    let currentIndex: Int
    let onGo: (Int) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var rangeText: String {
        pageCount > 0 ? "(1 – \(pageCount))" : "(no pages)"
    }

    /// The same page-number grammar as the find bar.
    private var parsedPage: Int? {
        PageNumberQuery.page(in: text, pageCount: pageCount)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("Go to Page")

            TextField("Page", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: 58)
                .focused($isFocused)
                .submitLabel(.go)
                .onSubmit(go)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif

            Text(rangeText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer(minLength: 0)

            Button("Go", action: go)
                .buttonStyle(.bordered)
                .disabled(parsedPage == nil)
        }
        .onAppear {
            text = "\(currentIndex + 1)"
        }
        #if os(iOS)
        // The number pad has no Return key, so the keyboard gets its own Go.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Go", action: go)
                    .disabled(parsedPage == nil)
            }
        }
        #endif
    }

    private func go() {
        guard let page = parsedPage else {
            text = "\(currentIndex + 1)"
            return
        }
        text = "\(page)"
        isFocused = false
        onGo(page - 1)
    }
}

#Preview("Go to Page") {
    GoToPageField(pageCount: 55, currentIndex: 21, onGo: { _ in })
        .padding()
        .frame(width: 340)
}
