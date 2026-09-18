import Foundation

/// A colour as plain components, so a palette and its contrast rules are values
/// a test can read without a screen.
public struct BrandColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `0xRRGGBB`, the form the brand sheet writes.
    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    public var hex: String {
        let value = { (channel: Double) in Int((channel * 255).rounded()) }
        return String(format: "#%02X%02X%02X", value(red), value(green), value(blue))
    }

    /// WCAG relative luminance.
    public var relativeLuminance: Double {
        0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    /// The WCAG contrast ratio against another colour, from 1 to 21.
    public func contrast(against other: BrandColor) -> Double {
        let mine = relativeLuminance
        let theirs = other.relativeLuminance
        return (max(mine, theirs) + 0.05) / (min(mine, theirs) + 0.05)
    }

    private static func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
}

/// The appearance the window renders in.
public enum Appearance: String, CaseIterable, Equatable, Sendable {
    case light
    case dark
}

/// What a status or state reads as, so a colour is never the only thing that
/// carries it.
public enum StatusTone: String, CaseIterable, Equatable, Sendable {
    case neutral
    case success
    case warning
    case danger
}

/// The brand's colours as code-defined tokens: the values the brand sheet names,
/// their derived steps, and a dark derivation of each. A token used as text
/// reaches 4.5:1 against every surface it renders on; a token used as a mark, a
/// fill or a border reaches 3:1.
public struct BrandPalette: Equatable, Sendable {
    // Surfaces
    public let background: BrandColor
    public let surface: BrandColor
    public let surfaceWarm: BrandColor
    public let sidebar: BrandColor
    public let well: BrandColor
    public let bar: BrandColor
    public let border: BrandColor

    // Text
    public let textPrimary: BrandColor
    public let textSecondary: BrandColor
    /// For non-text detail, or text at 18 points and above; never small text.
    public let muted: BrandColor

    // The accent, and the filled control's own pair
    public let accent: BrandColor
    public let accentFill: BrandColor
    public let accentFillHover: BrandColor
    public let accentOn: BrandColor

    // Status, as a mark and as text. Dark derivations are their own values.
    public let success: BrandColor
    public let warning: BrandColor
    public let danger: BrandColor
    public let successText: BrandColor
    public let warningText: BrandColor
    public let dangerText: BrandColor

    public static let light = BrandPalette(
        background: BrandColor(hex: 0xF7EEE6),
        surface: BrandColor(hex: 0xFFF8F1),
        surfaceWarm: BrandColor(hex: 0xEAD6C7),
        sidebar: BrandColor(hex: 0xF0E1D6),
        well: BrandColor(hex: 0xF9EEE4),
        bar: BrandColor(hex: 0xF9F0E8),
        border: BrandColor(hex: 0xDAC8B9),
        textPrimary: BrandColor(hex: 0x2B211C),
        textSecondary: BrandColor(hex: 0x5A4B43),
        muted: BrandColor(hex: 0x8A7A70),
        accent: BrandColor(hex: 0xB46A46),
        accentFill: BrandColor(hex: 0x935538),
        accentFillHover: BrandColor(hex: 0x804A30),
        accentOn: BrandColor(hex: 0xFFFFFF),
        success: BrandColor(hex: 0x4D8F5A),
        warning: BrandColor(hex: 0xAE7633),
        danger: BrandColor(hex: 0xB84C4C),
        successText: BrandColor(hex: 0x466C46),
        warningText: BrandColor(hex: 0x855C2F),
        dangerText: BrandColor(hex: 0xA14644)
    )

    public static let dark = BrandPalette(
        background: BrandColor(hex: 0x1C1411),
        surface: BrandColor(hex: 0x231A16),
        surfaceWarm: BrandColor(hex: 0x2B211C),
        sidebar: BrandColor(hex: 0x201814),
        well: BrandColor(hex: 0x180F0C),
        bar: BrandColor(hex: 0x281F1A),
        border: BrandColor(hex: 0x3B332E),
        textPrimary: BrandColor(hex: 0xF7EFE7),
        textSecondary: BrandColor(hex: 0xA39992),
        muted: BrandColor(hex: 0x796C65),
        accent: BrandColor(hex: 0xC38467),
        accentFill: BrandColor(hex: 0xC38467),
        accentFillHover: BrandColor(hex: 0xCA9076),
        accentOn: BrandColor(hex: 0x2B211C),
        success: BrandColor(hex: 0x5F9A6A),
        warning: BrandColor(hex: 0xC88735),
        danger: BrandColor(hex: 0xCA716E),
        successText: BrandColor(hex: 0x5F9A6A),
        warningText: BrandColor(hex: 0xC88735),
        dangerText: BrandColor(hex: 0xCA716E)
    )

    public static func palette(for appearance: Appearance) -> BrandPalette {
        switch appearance {
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The colour a status mark draws with.
    public func mark(_ tone: StatusTone) -> BrandColor {
        switch tone {
        case .neutral: return textSecondary
        case .success: return success
        case .warning: return warning
        case .danger: return danger
        }
    }

    /// The colour a status word draws with.
    public func text(_ tone: StatusTone) -> BrandColor {
        switch tone {
        case .neutral: return textSecondary
        case .success: return successText
        case .warning: return warningText
        case .danger: return dangerText
        }
    }
}
