import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A caret request handed from the document editor to one block's text view.
struct CaretRequest: Equatable {
    /// Changes per request so an old request is never applied twice.
    let token: UUID
    /// UTF-16 offset inside the block's text.
    let offset: Int
}

/// The type for one block, in a form both platforms can use.
///
/// The iPad editor needs a `UIFont` and the Mac fallback wants a SwiftUI
/// `Font`, so blocks describe the type once and each side converts it.
/// `textStyle` is the closest system text style for the block's size, so the
/// font follows the reader's Dynamic Type setting instead of staying at a
/// fixed point size.
struct BlockFont {
    var size: CGFloat
    var textStyle: Font.TextStyle = .body
    var weight: Font.Weight = .regular
    var isMonospaced = false
    var isItalic = false

    var font: Font {
        var font = Font.system(size: size, weight: weight, design: isMonospaced ? .monospaced : .default)
        if isItalic { font = font.italic() }
        return font
    }

    #if os(iOS)
    /// The font at the block's own size, scaled to the current text size.
    var uiFont: UIFont {
        UIFontMetrics(forTextStyle: textStyle.uiTextStyle).scaledFont(for: unscaledUIFont)
    }

    private var unscaledUIFont: UIFont {
        var font = isMonospaced
            ? UIFont.monospacedSystemFont(ofSize: size, weight: weight.uiWeight)
            : UIFont.systemFont(ofSize: size, weight: weight.uiWeight)
        if isItalic, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
            font = UIFont(descriptor: descriptor, size: size)
        }
        return font
    }
    #endif
}

#if os(iOS)
private extension Font.TextStyle {
    /// The `UIFont.TextStyle` whose scaling curve matches this style.
    var uiTextStyle: UIFont.TextStyle {
        if self == .largeTitle { return .largeTitle }
        if self == .title { return .title1 }
        if self == .title2 { return .title2 }
        if self == .title3 { return .title3 }
        if self == .headline { return .headline }
        if self == .subheadline { return .subheadline }
        if self == .callout { return .callout }
        if self == .footnote { return .footnote }
        if self == .caption { return .caption1 }
        if self == .caption2 { return .caption2 }
        return .body
    }
}
#endif

#if os(iOS)
private extension Font.Weight {
    var uiWeight: UIFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}
#endif

/// A borderless, self-sizing text view for one block of a document.
///
/// SwiftUI's `TextField` cannot report Return or a Backspace at offset zero, so
/// blocks are backed by `UITextView`. The view reports its own height, which
/// keeps the document scrolling as one page instead of nesting scroll views.
struct BlockTextEditor: View {
    @Binding var text: String
    var font: BlockFont
    var textColor: Color = .primary
    var placeholder: String = ""
    /// False for code, where Return starts a new line in the same block.
    var splitsOnReturn = true
    /// True while this block (or item) owns the caret.
    var isFocused = false
    /// A pending request to take focus and place the caret.
    var focusRequest: CaretRequest?

    var onReturn: (Int) -> Void = { _ in }
    var onBackspaceAtStart: () -> Void = {}
    var onFocus: () -> Void = {}
    var onBlur: () -> Void = {}

    var body: some View {
        #if os(iOS)
        Representable(
            text: $text,
            font: font.uiFont,
            textColor: UIColor(textColor),
            placeholder: placeholder,
            splitsOnReturn: splitsOnReturn,
            isFocused: isFocused,
            focusRequest: focusRequest,
            onReturn: onReturn,
            onBackspaceAtStart: onBackspaceAtStart,
            onFocus: onFocus,
            onBlur: onBlur
        )
        #else
        TextField(placeholder, text: $text, axis: .vertical)
            .font(font.font)
            .foregroundStyle(textColor)
            .textFieldStyle(.plain)
        #endif
    }
}

#if os(iOS)
extension BlockTextEditor {
    fileprivate struct Representable: UIViewRepresentable {
        @Binding var text: String
        var font: UIFont
        var textColor: UIColor
        var placeholder: String
        var splitsOnReturn: Bool
        var isFocused: Bool
        var focusRequest: CaretRequest?

        var onReturn: (Int) -> Void
        var onBackspaceAtStart: () -> Void
        var onFocus: () -> Void
        var onBlur: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        func makeUIView(context: Context) -> BlockTextView {
            let view = BlockTextView()
            view.delegate = context.coordinator
            view.backgroundColor = .clear
            view.isScrollEnabled = false
            view.isEditable = true
            view.isSelectable = true
            view.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
            view.textContainer.lineFragmentPadding = 0
            view.textContainer.widthTracksTextView = true
            view.adjustsFontForContentSizeCategory = true
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            view.font = font
            view.textColor = textColor
            view.text = text
            view.typingAttributes = [.font: font, .foregroundColor: textColor]

            let label = UILabel()
            label.text = placeholder
            label.font = font
            label.textColor = .tertiaryLabel
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                label.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
                label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
            ])
            label.isHidden = !text.isEmpty

            let coordinator = context.coordinator
            coordinator.view = view
            coordinator.placeholder = label
            view.onMovedToWindow = { [weak coordinator] in
                coordinator?.applyFocusIfNeeded()
            }
            view.onDeleteBackwardAtStart = { [weak coordinator] in
                coordinator?.parent.onBackspaceAtStart()
            }
            return view
        }

        func updateUIView(_ view: BlockTextView, context: Context) {
            let coordinator = context.coordinator
            coordinator.parent = self
            coordinator.view = view

            let label = coordinator.placeholder
            let hidesPlaceholder = !text.isEmpty
            let textChanged = view.text != text
            let styleChanged = view.font != font
                || view.textColor != textColor
                || view.typingAttributes[.font] as? UIFont != font
                || view.typingAttributes[.foregroundColor] as? UIColor != textColor
            let placeholderChanged = label?.text != placeholder
                || label?.font != font
                || label?.isHidden != hidesPlaceholder

            // Everything this update would apply is already applied: a
            // keystroke stays in the text view, and no text is reset (which
            // would move the caret to the end).
            guard textChanged || styleChanged || placeholderChanged else {
                coordinator.applyFocusIfNeeded()
                return
            }

            if styleChanged {
                if view.font != font {
                    view.font = font
                }
                if view.textColor != textColor {
                    view.textColor = textColor
                }
                view.typingAttributes = [.font: font, .foregroundColor: textColor]
            }

            // Only push model text in when the view does not already show it,
            // so typing never rewrites the buffer and resets the caret.
            if textChanged {
                let selection = view.selectedRange
                view.text = text
                view.font = font
                view.textColor = textColor
                if view.isFirstResponder {
                    view.selectedRange = NSRange(
                        location: min(selection.location, (text as NSString).length),
                        length: 0
                    )
                }
            }

            if placeholderChanged {
                label?.text = placeholder
                label?.font = font
                label?.isHidden = hidesPlaceholder
            }

            coordinator.applyFocusIfNeeded()
        }

        func sizeThatFits(
            _ proposal: ProposedViewSize,
            uiView: BlockTextView,
            context: Context
        ) -> CGSize? {
            let width = proposal.width ?? uiView.bounds.width
            guard width.isFinite, width > 0 else { return nil }
            let fitted = uiView.sizeThatFits(
                CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            )
            return CGSize(width: width, height: max(ceil(fitted.height), 26))
        }

        @MainActor
        final class Coordinator: NSObject, UITextViewDelegate {
            var parent: Representable
            weak var view: BlockTextView?
            var placeholder: UILabel?
            private var appliedToken: UUID?

            init(parent: Representable) {
                self.parent = parent
            }

            func applyFocusIfNeeded() {
                guard let view else { return }

                if let request = parent.focusRequest, request.token != appliedToken {
                    let offset = request.offset
                    // Mark the token applied only once the view is really in a
                    // window. In the lazy block list a row that is off screen
                    // does not exist yet; the token then stays pending and
                    // `BlockTextView.didMoveToWindow` retries it when the row
                    // appears.
                    DispatchQueue.main.async { [weak self, weak view] in
                        guard let self, let view, view.window != nil else { return }
                        self.appliedToken = request.token
                        if !view.isFirstResponder {
                            view.becomeFirstResponder()
                        }
                        let length = (view.text as NSString).length
                        view.selectedRange = NSRange(location: min(max(offset, 0), length), length: 0)
                    }
                    return
                }

                if !parent.isFocused, view.isFirstResponder {
                    view.resignFirstResponder()
                }
            }

            func textView(
                _ textView: UITextView,
                shouldChangeTextIn range: NSRange,
                replacementText text: String
            ) -> Bool {
                // Let the input method finish composing before acting on keys.
                if textView.markedTextRange != nil { return true }

                if text == "\n" {
                    guard parent.splitsOnReturn else { return true }
                    parent.onReturn(textView.selectedRange.location)
                    return false
                }

                return true
            }

            func textViewDidChange(_ textView: UITextView) {
                guard parent.text != textView.text else { return }
                parent.text = textView.text
            }

            func textViewDidBeginEditing(_ textView: UITextView) {
                if let token = parent.focusRequest?.token {
                    appliedToken = token
                }
                parent.onFocus()
            }

            func textViewDidEndEditing(_ textView: UITextView) {
                parent.onBlur()
            }
        }
    }
}

/// A text view that calls back once it is in a window, so a newly inserted
/// block can take focus even though it is not on screen when it is created.
///
/// Backspace at offset zero is caught in `deleteBackward()`: UIKit does not
/// consult the text-view delegate when there is no character to delete, which
/// is exactly the case an editor needs to turn into "merge with the block
/// above".
final class BlockTextView: UITextView {
    var onMovedToWindow: (() -> Void)?
    var onDeleteBackwardAtStart: (() -> Void)?

    /// The document editor keeps one snapshot stack for the whole page. A
    /// per-field stack would replay the same keystrokes into a second history,
    /// so the block opts out of the system undo manager entirely.
    override var undoManager: UndoManager? { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        onMovedToWindow?()
    }

    override func deleteBackward() {
        if markedTextRange == nil, selectedRange.location == 0, selectedRange.length == 0 {
            onDeleteBackwardAtStart?()
            return
        }
        super.deleteBackward()
    }
}
#endif
