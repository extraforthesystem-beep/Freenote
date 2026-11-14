#if os(iOS)
import SwiftUI
import TipKit

/// Teaches the canvas's two-finger double-tap undo, once per install.
///
/// The toolbar's Undo and Redo buttons are visible, but the faster gesture is
/// not; TipKit keeps this from coming back once it has been read or dismissed.
struct UndoGestureTip: Tip {
    var title: Text {
        Text("Undo with a gesture")
    }

    var message: Text? {
        Text("Double-tap with two fingers to undo, three fingers to redo.")
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
