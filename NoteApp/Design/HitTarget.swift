import SwiftUI

extension View {
    /// 44 pt is the minimum touch target on iPad. Grows the tappable frame
    /// without changing how the content inside is drawn.
    func hitTarget(_ side: CGFloat = 44) -> some View {
        frame(minWidth: side, minHeight: side).contentShape(Rectangle())
    }
}
