import AppKit
import XCTest
@testable import Paper

final class PaperThemeTests: XCTestCase {

    // MARK: - Resolution helpers

    /// Resolves a (possibly dynamic) color for one appearance.
    ///
    /// Component reads must happen inside a drawing-appearance context, or a
    /// dynamic color resolves against whatever appearance happened to be
    /// current — the same hazard that makes an app paint light after launching
    /// in dark mode.
    private func resolved(_ color: NSColor, in name: NSAppearance.Name) throws -> NSColor {
        let appearance = try XCTUnwrap(NSAppearance(named: name), "unknown appearance \(name)")
        var result: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB)
        }
        return try XCTUnwrap(result, "could not resolve \(color) in \(name)")
    }

    private func luminance(_ color: NSColor) -> CGFloat {
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent)
            + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
    }

    private func contrastRatio(_ first: NSColor, _ second: NSColor) -> CGFloat {
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private var lightAppearance: NSAppearance.Name { .aqua }
    private var darkAppearance: NSAppearance.Name { .darkAqua }

    // MARK: - R6: the light appearance is unchanged

    func testLightTokensKeepShippedValues() throws {
        // Tolerance absorbs the generic-RGB to sRGB conversion of the values
        // Paper shipped before the palette became sRGB-based.
        let shipped: [(NSColor, (CGFloat, CGFloat, CGFloat))] = [
            (PaperTheme.nsAccent, (0.91, 0.31, 0.06)),
            (PaperTheme.nsEditorBackground, (0.99, 0.99, 0.98)),
            (PaperTheme.nsGutterBackground, (0.95, 0.95, 0.94)),
            (PaperTheme.nsGutterText, (0.30, 0.30, 0.32)),
            (PaperTheme.nsDivider, (0.84, 0.84, 0.83)),
            (PaperTheme.nsEditorText, (0.08, 0.08, 0.09)),
        ]

        for (token, expected) in shipped {
            let color = try resolved(token, in: lightAppearance)
            XCTAssertEqual(color.redComponent, expected.0, accuracy: 0.02)
            XCTAssertEqual(color.greenComponent, expected.1, accuracy: 0.02)
            XCTAssertEqual(color.blueComponent, expected.2, accuracy: 0.02)
        }
    }

    // MARK: - R1/R3: the palette actually adapts, and the dark palette is ordered

    func testTokensResolveDifferentlyInDarkAppearance() throws {
        let tokens: [(String, NSColor)] = [
            ("accent", PaperTheme.nsAccent),
            ("editorBackground", PaperTheme.nsEditorBackground),
            ("gutterBackground", PaperTheme.nsGutterBackground),
            ("gutterText", PaperTheme.nsGutterText),
            ("divider", PaperTheme.nsDivider),
            ("editorText", PaperTheme.nsEditorText),
        ]

        for (name, token) in tokens {
            let light = try resolved(token, in: lightAppearance)
            let dark = try resolved(token, in: darkAppearance)
            XCTAssertNotEqual(
                [light.redComponent, light.greenComponent, light.blueComponent],
                [dark.redComponent, dark.greenComponent, dark.blueComponent],
                "\(name) did not adapt to dark appearance"
            )
        }
    }

    func testDarkCanvasIsDarkerAndGutterIsLighterThanCanvas() throws {
        let lightCanvas = try resolved(PaperTheme.nsEditorBackground, in: lightAppearance)
        let darkCanvas = try resolved(PaperTheme.nsEditorBackground, in: darkAppearance)
        let darkGutter = try resolved(PaperTheme.nsGutterBackground, in: darkAppearance)

        XCTAssertLessThan(luminance(darkCanvas), luminance(lightCanvas))
        XCTAssertGreaterThan(luminance(darkGutter), luminance(darkCanvas))
    }

    func testDarkCanvasIsWarmRatherThanNeutral() throws {
        let canvas = try resolved(PaperTheme.nsEditorBackground, in: darkAppearance)
        XCTAssertGreaterThan(canvas.redComponent, canvas.blueComponent)
    }

    // MARK: - R4: contrast thresholds

    func testTextContrastMeetsThresholdInBothAppearances() throws {
        for appearance in [lightAppearance, darkAppearance] {
            let canvas = try resolved(PaperTheme.nsEditorBackground, in: appearance)
            let text = try resolved(PaperTheme.nsEditorText, in: appearance)
            XCTAssertGreaterThanOrEqual(
                contrastRatio(text, canvas), 4.5,
                "body text on canvas fell below 4.5:1 in \(appearance.rawValue)"
            )

            let gutter = try resolved(PaperTheme.nsGutterBackground, in: appearance)
            let numbers = try resolved(PaperTheme.nsGutterText, in: appearance)
            XCTAssertGreaterThanOrEqual(
                contrastRatio(numbers, gutter), 4.5,
                "line numbers on gutter fell below 4.5:1 in \(appearance.rawValue)"
            )
        }
    }

    // MARK: - R5: the accent stays legible

    func testAccentIsLegibleOnCanvasInBothAppearances() throws {
        for appearance in [lightAppearance, darkAppearance] {
            let canvas = try resolved(PaperTheme.nsEditorBackground, in: appearance)
            let accent = try resolved(PaperTheme.nsAccent, in: appearance)
            XCTAssertGreaterThanOrEqual(
                contrastRatio(accent, canvas), 3.0,
                "caret accent fell below 3:1 on the canvas in \(appearance.rawValue)"
            )
        }
    }

    // MARK: - KTD1: vibrant and high-contrast appearances resolve, never fall back

    func testHighContrastDarkAppearancesDoNotFallBackToLight() throws {
        let variants: [NSAppearance.Name] = [
            .vibrantDark,
            .accessibilityHighContrastDarkAqua,
            .accessibilityHighContrastVibrantDark,
        ]

        for name in variants {
            let canvas = try resolved(PaperTheme.nsEditorBackground, in: name)
            let lightCanvas = try resolved(PaperTheme.nsEditorBackground, in: lightAppearance)
            XCTAssertEqual(canvas.redComponent, canvas.redComponent)
            XCTAssertLessThan(
                luminance(canvas), luminance(lightCanvas),
                "\(name.rawValue) resolved to the light canvas"
            )
        }
    }

    func testLightVariantsResolveToLightValues() throws {
        let variants: [NSAppearance.Name] = [
            .vibrantLight,
            .accessibilityHighContrastAqua,
            .accessibilityHighContrastVibrantLight,
        ]

        for name in variants {
            let canvas = try resolved(PaperTheme.nsEditorBackground, in: name)
            XCTAssertGreaterThan(
                luminance(canvas), 0.5,
                "\(name.rawValue) did not resolve to a light canvas"
            )
        }
    }
}
