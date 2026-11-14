#if os(iOS)
import SwiftUI
import TipKit

/// Teaches the canvas's two-finger double-tap undo, once per install.
///
/// The gesture has no visible control, so a tip is the only place a new reader
/// can learn it; TipKit keeps it from coming back once it has been read or
/// dismissed.
struct UndoGestureTip: Tip {
    var title: Text {
        Text("Undo with a gesture")
    }

    var message: Text? {
        Text("Tip: double-tap with two fingers to undo, three fingers to redo.")
    }

    var image: Image? {
        Image(systemName: "hand.tap")
    }
}

/// The tip as it appears over the top of the page: narrow enough to read as a
/// hint rather than a panel, and dismissible with its close button.
struct UndoGestureTipView: View {
    var body: some View {
        TipView(UndoGestureTip())
            .frame(maxWidth: 420)
            .padding(.horizontal, AppSpacing.l)
    }
}
#endif
