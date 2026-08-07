import SwiftUI
import UIKit

// MARK: - Color helpers

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

/// A color that resolves differently in light and dark mode.
func adaptiveColor(dark: UIColor, light: UIColor) -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
    })
}

// MARK: - Palette
//
// Implements the "Music Library Client" design system: one saturated
// indigo-violet carrying brand and state, hierarchy from surface *value* rather
// than borders and shadows, and a strict canvas → surface → surface-2 →
// surface-3 nesting that inverts between themes (nested cards get lighter on
// dark, and return to white on light).

enum Palette {
    // MARK: Primary ramp
    //
    // The single brand hue. Tints — never a second hue — carry hierarchy.
    // `primary500` is the value that must survive theme switching; it reads on
    // both the near-black canvas and white.
    static let primary900 = Color(hex: 0x2A1BD1)
    static let primary700 = Color(hex: 0x3826EA)
    static let primary600 = Color(hex: 0x4B3FE8)
    static let primary500 = Color(hex: 0x6C63E8)
    static let primary400 = Color(hex: 0x8F88EE)
    static let primary300 = Color(hex: 0xB4AFF4)
    static let primary200 = Color(hex: 0xD6D3FA)
    static let primary100 = Color(hex: 0xE9E7FC)

    /// Core accent — progress fills, active state, filled stars.
    static let accent = primary500
    /// Links and nav-bar actions: the brighter tint on dark, a deeper one on light.
    static let tint = adaptiveColor(dark: UIColor(hex: 0x6C63E8), light: UIColor(hex: 0x4B3FE8))
    /// Hero / primary button fill.
    static let primaryFill = adaptiveColor(dark: UIColor(hex: 0x4B3FE8), light: UIColor(hex: 0x3826EA))

    // MARK: Surfaces
    //
    // Elevation always moves *toward* the opposite pole of the theme.
    static let background = adaptiveColor(dark: UIColor(hex: 0x0E0E0E), light: .white)
    /// Nav bar / bottom chrome — one step off the canvas.
    static let chrome = adaptiveColor(dark: UIColor(hex: 0x131313), light: UIColor(hex: 0xFAFAFA))
    /// Section container and cards sitting directly on the canvas.
    static let grouped = adaptiveColor(dark: UIColor(hex: 0x1A1A1A), light: UIColor(hex: 0xF4F5F7))
    /// A card nested inside a section — white again on light.
    static let surface2 = adaptiveColor(dark: UIColor(hex: 0x232323), light: .white)
    /// Pills, chips, secondary buttons, popovers.
    static let fill = adaptiveColor(dark: UIColor(hex: 0x2E2E2E), light: UIColor(hex: 0xE9EBEF))
    /// Sheets and dropdowns over a scrim.
    static let overlay = adaptiveColor(dark: UIColor(hex: 0x3A3A3A), light: .white)
    /// Selected segment in a segmented control.
    static let segmentSelected = adaptiveColor(dark: UIColor(hex: 0x3A3A3A), light: .white)
    /// Track behind search fields and segmented controls.
    static let controlFill = adaptiveColor(dark: UIColor(hex: 0x232323), light: UIColor(hex: 0xE9EBEF))

    // MARK: Text
    static let label = adaptiveColor(dark: .white, light: UIColor(hex: 0x111214))
    static let secondary = adaptiveColor(dark: UIColor(hex: 0xB4B4B4), light: UIColor(hex: 0x5A5E66))
    static let tertiary = adaptiveColor(dark: UIColor(hex: 0x7C7C7C), light: UIColor(hex: 0x8A8F98))
    static let quaternary = adaptiveColor(dark: UIColor(hex: 0x5A5A5A), light: UIColor(hex: 0xA8ADB5))
    static let onPrimary = Color.white
    static let onPrimaryDim = Color.white.opacity(0.72)

    // MARK: Lines
    /// Card hairline.
    static let separator = adaptiveColor(dark: UIColor(hex: 0x2A2A2A), light: UIColor(hex: 0xE3E5EA))
    /// Full-width rule under a section title.
    static let rule = adaptiveColor(dark: UIColor(hex: 0x3A3A3A), light: UIColor(hex: 0xD9DCE2))
    static let starEmpty = adaptiveColor(dark: UIColor(hex: 0x3A3A3A), light: UIColor(hex: 0xD9DCE2))

    // MARK: Semantic
    /// Used once per screen at most, never as a large fill.
    static let accentWarm = Color(hex: 0xE8462F)
    static let danger = Color(hex: 0xF0453B)
    static let positive = adaptiveColor(dark: UIColor(hex: 0x3FB463), light: UIColor(hex: 0x1F8A47))
    /// The deliberately desaturated "other" bucket.
    static let neutral = Color(hex: 0x6B6B6B)
    static let iCloudBlue = primary600

    // MARK: Condition badges
    //
    // Grades stay semantic — they're a quality signal, not a brand surface —
    // but sit at the system's saturation so they don't shout.
    static let badgeGreenText = adaptiveColor(dark: UIColor(hex: 0x4FC97A), light: UIColor(hex: 0x1F8A47))
    static let badgeGreenFill = Color(hex: 0x3FB463, opacity: 0.16)
    static let badgeAmberText = adaptiveColor(dark: UIColor(hex: 0xE0A44A), light: UIColor(hex: 0x8A6410))
    static let badgeAmberFill = Color(hex: 0xE0A44A, opacity: 0.16)
    static let badgeNeutralFill = adaptiveColor(dark: UIColor(white: 1, alpha: 0.10),
                                                light: UIColor(hex: 0x3C3C43, alpha: 0.08))

    /// Solid fills for a *selected* grade chip, paired with white text.
    static let gradeGreenSolid = adaptiveColor(dark: UIColor(hex: 0x2F9D57), light: UIColor(hex: 0x1F8A47))
    static let gradeAmberSolid = adaptiveColor(dark: UIColor(hex: 0xA8761A), light: UIColor(hex: 0x8A6410))
    static let gradeSlateSolid = adaptiveColor(dark: UIColor(hex: 0x6B6B6B), light: UIColor(hex: 0x5A5E66))
    static let gradeRedSolid = adaptiveColor(dark: UIColor(hex: 0xC8413A), light: UIColor(hex: 0xB0322B))
}

// MARK: - Typography
//
// The design system's two families, bundled from their upstream open-source
// releases (SIL OFL — see Resources/Fonts/LICENSE.txt): Inter Tight for the UI
// and Playfair Display for the one display moment per screen. Only three
// weights exist — 400/500 for content, 600 for anything structural.
//
// `Font.custom` falls back to the system font if a face fails to register, so
// the app still renders if those resources ever go missing.

enum TypeFace {
    /// Inter Tight at a design weight. PostScript names come from the instanced
    /// statics: InterTight-Regular / -Medium / -SemiBold.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let suffix: String
        switch weight {
        case .semibold, .bold, .heavy, .black: suffix = "SemiBold"
        case .medium: suffix = "Medium"
        default: suffix = "Regular"
        }
        return .custom("InterTight-\(suffix)", size: size)
    }

    static func display(_ size: CGFloat) -> Font {
        .custom("PlayfairDisplay-Regular", size: size)
    }
}

extension Font {
    /// Display — the single expressive moment on a screen (Playfair Display).
    static let prDisplay = TypeFace.display(40)
    /// Numeric value on a stat card (tabular).
    static let prStatValue = TypeFace.ui(24, .semibold).monospacedDigit()
    /// Mono metadata — the year on a tile, the format on a row. The design's
    /// mono is a system stack, so this stays on the system monospace.
    static let prMonoTiny = Font.system(size: 9, weight: .regular, design: .monospaced)
    static let prMonoSmall = Font.system(size: 10, weight: .regular, design: .monospaced)
    static let prStat = TypeFace.ui(32, .semibold).monospacedDigit()

    static let prLargeTitle = TypeFace.ui(30, .semibold)
    /// h1 — page titles.
    static let prTitle = TypeFace.ui(24, .semibold)
    static let prTitle2 = TypeFace.ui(20, .semibold)
    /// h2 — section headings ("Tracklist", "Notes").
    static let prSection = TypeFace.ui(18, .semibold)
    /// h3 — card headings.
    static let prHeadline = TypeFace.ui(16, .semibold)

    /// body — track titles, list rows.
    static let prBody = TypeFace.ui(15, .medium)
    static let prBodyEmphasis = TypeFace.ui(15, .semibold)
    /// body-sm — secondary lines.
    static let prSmall = TypeFace.ui(13)
    static let prFootnote = TypeFace.ui(13)
    /// caption — timestamps, counts.
    static let prCaptionSm = TypeFace.ui(12)
    /// Numeric caption, tabular so counts don't jitter.
    static let prNumeric = TypeFace.ui(13, .medium).monospacedDigit()

    /// overline — uppercase structural labels. Pair with `Metrics.overlineTracking`.
    static let prCaption = TypeFace.ui(11, .semibold)
    static let prBadge = TypeFace.ui(11, .semibold)

    static let prNav = TypeFace.ui(16, .medium)
    static let prNavBold = TypeFace.ui(16, .semibold)
}

// MARK: - Metrics

enum Metrics {
    /// Mobile outer margin (4px grid).
    static let screenPadding: CGFloat = 16

    // Radius: containers are square-ish, controls are fully round. There is no
    // intermediate button radius in this system.
    /// Progress bars and hairline fills.
    static let barRadius: CGFloat = 2
    /// Album art, chips, swatches.
    static let tileRadius: CGFloat = 4
    /// The dominant radius — cards and section containers.
    static let cardRadius: CGFloat = 6
    static let smallCardRadius: CGFloat = 6
    /// Sheets, dropdowns, popovers.
    static let overlayRadius: CGFloat = 10
    /// All buttons, badges, avatars.
    static let pillRadius: CGFloat = 999
    static let buttonRadius: CGFloat = 999
    static let badgeRadius: CGFloat = 999

    // Spacing (4px base grid).
    static let sectionPadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let cardGap: CGFloat = 16
    static let sectionGap: CGFloat = 32
    static let rowGap: CGFloat = 16
    static let rowPadding: CGFloat = 12

    /// Uppercase overline tracking (0.08em at 11pt).
    static let overlineTracking: CGFloat = 0.88

    /// Minimum hit area, expanded with invisible inset where the control is smaller.
    static let minTouchTarget: CGFloat = 44
}
