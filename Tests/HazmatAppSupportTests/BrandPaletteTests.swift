import Foundation
import XCTest
@testable import HazmatAppSupport

/// The brand's tokens and the contrast rules they carry: text reaches 4.5:1
/// against what it sits on, non-text UI reaches 3:1, and the dark appearance
/// derives its own values.
final class BrandPaletteTests: XCTestCase {
    private let appearances: [Appearance] = [.light, .dark]

    private func surfaces(_ palette: BrandPalette) -> [BrandColor] {
        [palette.background, palette.surface, palette.sidebar, palette.well]
    }

    private func assertContrast(
        _ colour: BrandColor,
        _ minimum: Double,
        _ what: String,
        in palette: BrandPalette,
        surfaces surfacesOverride: [BrandColor]? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for surface in surfacesOverride ?? surfaces(palette) {
            let ratio = colour.contrast(against: surface)
            XCTAssertGreaterThanOrEqual(
                ratio,
                minimum,
                "\(what) \(colour.hex) on \(surface.hex) is \(String(format: "%.2f", ratio)):1, below \(minimum):1"
            )
        }
    }

    func testEveryTextTierReachesFourPointFiveToOne() {
        for appearance in appearances {
            let palette = BrandPalette.palette(for: appearance)
            assertContrast(palette.textPrimary, 4.5, "the first text tier", in: palette)
            assertContrast(palette.textSecondary, 4.5, "the second text tier", in: palette)
            assertContrast(palette.successText, 4.5, "the success word", in: palette)
            assertContrast(palette.warningText, 4.5, "the warning word", in: palette)
            assertContrast(palette.dangerText, 4.5, "the danger word", in: palette)
        }
    }

    func testEveryNonTextTokenReachesThreeToOne() {
        for appearance in appearances {
            let palette = BrandPalette.palette(for: appearance)
            assertContrast(palette.accent, 3, "the accent", in: palette)
            assertContrast(palette.success, 3, "the success mark", in: palette)
            assertContrast(palette.warning, 3, "the warning mark", in: palette)
            assertContrast(palette.danger, 3, "the danger mark", in: palette)
            assertContrast(palette.border, 1.2, "the border", in: palette)
        }
    }

    func testTheFilledControlCarriesALabelItCanBeReadOn() {
        for appearance in appearances {
            let palette = BrandPalette.palette(for: appearance)
            let ratio = palette.accentOn.contrast(against: palette.accentFill)
            XCTAssertGreaterThanOrEqual(
                ratio,
                4.5,
                "\(palette.accentOn.hex) on the fill \(palette.accentFill.hex) is \(String(format: "%.2f", ratio)):1"
            )
        }
    }

    func testTheMutedTierIsForNonTextOrLargeTextOnTheSurfacesItIsUsedOn() {
        for appearance in appearances {
            let palette = BrandPalette.palette(for: appearance)
            assertContrast(
                palette.muted,
                3,
                "the muted tier",
                in: palette,
                surfaces: [palette.background, palette.surface, palette.well]
            )
        }
    }

    func testTheDarkAppearanceDerivesItsOwnValues() {
        let light = BrandPalette.light
        let dark = BrandPalette.dark

        XCTAssertNotEqual(light.background, dark.background)
        XCTAssertNotEqual(light.textPrimary, dark.textPrimary)
        XCTAssertNotEqual(light.accent, dark.accent)
        XCTAssertNotEqual(light.accentFill, dark.accentFill)
        XCTAssertNotEqual(light.sidebar, dark.sidebar)
        XCTAssertEqual(
            appearances.map { BrandPalette.palette(for: $0) },
            [.light, .dark]
        )
    }

    func testTheAccentAndItsFillAreDifferentSteps() {
        let light = BrandPalette.light

        XCTAssertNotEqual(light.accent, light.accentFill)
        XCTAssertLessThan(
            light.accentFill.relativeLuminance,
            light.accent.relativeLuminance,
            "the fill is the darker step"
        )
        XCTAssertLessThan(light.accentFillHover.relativeLuminance, light.accentFill.relativeLuminance)
    }

    func testEveryStatusToneCarriesAGlyphAWordAndAColourTogether() {
        let palette = BrandPalette.light

        XCTAssertEqual(palette.mark(.neutral), palette.textSecondary)
        XCTAssertEqual(palette.text(.neutral), palette.textSecondary)
        XCTAssertEqual(Set(StatusTone.allCases.map { palette.mark($0).hex }).count, StatusTone.allCases.count)

        for helper in HelperState.allCases {
            XCTAssertFalse(helper.label.isEmpty)
            XCTAssertFalse(helper.symbolName.isEmpty)
            XCTAssertFalse(helper.writeBlockCause.isEmpty)
        }
    }

    func testTheColourIsReportedAsHexAndContrastIsSymmetric() {
        let white = BrandColor(hex: 0xFFFFFF)
        let black = BrandColor(hex: 0x000000)

        XCTAssertEqual(white.hex, "#FFFFFF")
        XCTAssertEqual(black.hex, "#000000")
        XCTAssertEqual(white.contrast(against: black), 21, accuracy: 0.01)
        XCTAssertEqual(black.contrast(against: white), 21, accuracy: 0.01)
        XCTAssertEqual(white.contrast(against: white), 1, accuracy: 0.01)
    }
}
