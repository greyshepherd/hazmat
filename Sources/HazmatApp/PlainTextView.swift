import AppKit
import SwiftUI

/// Plain text that lays out only what is visible: an `NSTextView` in an
/// `NSScrollView`, which is what makes a hundred thousand lines usable where a
/// SwiftUI `Text` or `TextEditor` is not.
///
/// The text flows out through `onEdit` when it is changed, and flows in only
/// when the view does not already hold what it is given, so an edit never
/// round-trips the whole document back into the view.
struct PlainTextView: NSViewRepresentable {
    /// The text the view shows.
    var text: String
    /// Whether the text can be changed. A read-only view is still selectable, so
    /// the block can be selected and copied.
    var isEditable = false
    /// Called with the whole text when it changes.
    var onEdit: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        // A hosts file is not prose: nothing here may rewrite what was typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = Self.font
        textView.textContainerInset = NSSize(width: 4, height: 6)
        // The whole point: only the lines on screen are laid out.
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.delegate = context.coordinator
        textView.string = text

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        textView.isEditable = isEditable

        // Giving the view text it already holds would move the insertion point
        // and undo stack for nothing, and is how an edit would echo back.
        guard textView.string != text else { return }
        context.coordinator.isApplying = true
        textView.string = text
        context.coordinator.isApplying = false
    }

    static var font: NSFont {
        NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextView
        weak var textView: NSTextView?
        /// Whether the view is being given text rather than being edited, so a
        /// change that came from here is not reported as the user's.
        var isApplying = false

        init(_ parent: PlainTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplying, let textView = notification.object as? NSTextView else { return }
            parent.onEdit?(textView.string)
        }
    }
}
