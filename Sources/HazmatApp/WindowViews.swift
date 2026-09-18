import HazmatAppSupport
import SwiftUI

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
