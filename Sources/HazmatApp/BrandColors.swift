import HazmatAppSupport
import SwiftUI

extension BrandColor {
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

extension BrandPalette {
    static func forAppearance(_ scheme: ColorScheme) -> BrandPalette {
        scheme == .dark ? .dark : .light
    }
}

private struct BrandPaletteKey: EnvironmentKey {
    static let defaultValue = BrandPalette.light
}

extension EnvironmentValues {
    /// The palette for the appearance the window is rendering in. Set once at
    /// the root, so no control falls back to the system accent.
    var brand: BrandPalette {
        get { self[BrandPaletteKey.self] }
        set { self[BrandPaletteKey.self] = newValue }
    }
}

/// A state carried by a glyph, a word and a colour together, never by colour
/// alone.
struct StatusLabel: View {
    let symbolName: String
    let word: String
    let tone: StatusTone
    let palette: BrandPalette
    var font: Font = .callout

    var body: some View {
        Label {
            Text(word)
                .font(font)
                .foregroundStyle(palette.text(tone).color)
        } icon: {
            Image(systemName: symbolName)
                .foregroundStyle(palette.mark(tone).color)
        }
    }
}

/// The one prominently styled action of a phase: the accent's darker fill step,
/// with the label colour the contrast test measures against it.
struct PrimaryActionButton: View {
    let action: WindowAction
    let palette: BrandPalette
    let perform: (WindowAction) -> Void

    var body: some View {
        Button {
            perform(action)
        } label: {
            Text(action.title)
                .foregroundStyle(palette.accentOn.color)
        }
        .buttonStyle(.borderedProminent)
        .tint(palette.accentFill.color)
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
    let palette: BrandPalette
    let perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(palette.textPrimary.color)
            Text(detail)
                .font(.callout)
                .foregroundStyle(palette.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                perform()
            } label: {
                Label(actionTitle, systemImage: actionSymbol)
            }
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(palette.well.color, in: RoundedRectangle(cornerRadius: 8))
    }
}
