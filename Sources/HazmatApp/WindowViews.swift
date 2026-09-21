import AppKit
import HazmatAppSupport
import SwiftUI

/// The window the shell is in, so a keystroke that acts on the sidebar's
/// selection can require the window showing it to be the key one: a sheet, the
/// settings window and the store chooser are each key at times, and none of them
/// shows the row the keystroke would act on.
struct WindowReader: NSViewRepresentable {
    let tell: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReportingView {
        ReportingView(tell: tell)
    }

    func updateNSView(_ nsView: ReportingView, context: Context) {
        nsView.tell = tell
    }

    /// Tells of its window the moment it is in one — or out of one — rather
    /// than on a later update, which a window open since launch may never get
    /// before it closes.
    final class ReportingView: NSView {
        var tell: (NSWindow?) -> Void

        init(tell: @escaping (NSWindow?) -> Void) {
            self.tell = tell
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tell(window)
        }
    }
}

extension StatusTone {
    /// The colour the system pairs with a state. A state is still carried by a
    /// glyph and a word as well, never by colour alone.
    var color: Color {
        switch self {
        case .neutral: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .danger: return .red
        }
    }
}

/// A state carried by a glyph, a word and a colour together, never by colour
/// alone.
struct StatusLabel: View {
    let symbolName: String
    let word: String
    let tone: StatusTone
    var font: Font = .callout

    var body: some View {
        Label {
            Text(word)
                .font(font)
                .foregroundStyle(tone.color)
        } icon: {
            Image(systemName: symbolName)
                .foregroundStyle(tone.color)
        }
    }
}

/// The one prominently styled action of a phase, filled with the accent the
/// system resolves for the user's choice.
struct PrimaryActionButton: View {
    let action: WindowAction
    let perform: (WindowAction) -> Void

    var body: some View {
        Button {
            perform(action)
        } label: {
            Text(action.title)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityLabel(Text(action.title))
        .help(action.title)
    }
}

/// The label, description and action an empty list or pane carries.
struct EmptyStateView: View {
    let title: String
    let detail: String
    let actionTitle: String
    let actionSymbol: String
    let perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                perform()
            } label: {
                Label(actionTitle, systemImage: actionSymbol)
            }
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
