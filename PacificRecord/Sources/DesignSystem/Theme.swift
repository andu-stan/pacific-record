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

// MARK: - Palette (from the Pacific Record design tokens)

enum Palette {
    /// Amber — primary buttons, cover accents, filled stars. Same in both modes.
    static let accent = Color(hex: 0xD2691E)
    /// Tint for links / nav-bar actions (lighter amber on dark, deeper on light).
    static let tint = adaptiveColor(dark: UIColor(hex: 0xE8833A), light: UIColor(hex: 0xC85D17))

    static let background = adaptiveColor(dark: .black, light: UIColor(hex: 0xF2F2F7))
    /// Grouped card surface.
    static let grouped = adaptiveColor(dark: UIColor(hex: 0x1C1C1E), light: .white)
    /// Secondary fill — secondary buttons, chips.
    static let fill = adaptiveColor(dark: UIColor(hex: 0x2C2C2E), light: .white)
    /// Selected segment in a segmented control.
    static let segmentSelected = adaptiveColor(dark: UIColor(hex: 0x48484A), light: .white)
    /// Track for search fields / segmented controls (translucent gray in light).
    static let controlFill = adaptiveColor(dark: UIColor(hex: 0x1C1C1E),
                                           light: UIColor(hex: 0x767680, alpha: 0.12))

    static let label = adaptiveColor(dark: .white, light: .black)
    static let secondary = adaptiveColor(dark: UIColor(hex: 0xEBEBF5, alpha: 0.60),
                                         light: UIColor(hex: 0x3C3C43, alpha: 0.60))
    static let tertiary = adaptiveColor(dark: UIColor(hex: 0xEBEBF5, alpha: 0.50),
                                        light: UIColor(hex: 0x3C3C43, alpha: 0.50))
    static let quaternary = adaptiveColor(dark: UIColor(hex: 0xEBEBF5, alpha: 0.30),
                                          light: UIColor(hex: 0x3C3C43, alpha: 0.30))
    static let separator = adaptiveColor(dark: UIColor(white: 1, alpha: 0.07),
                                         light: UIColor(hex: 0x3C3C43, alpha: 0.12))
    static let starEmpty = adaptiveColor(dark: UIColor(hex: 0xEBEBF5, alpha: 0.25),
                                         light: UIColor(hex: 0x3C3C43, alpha: 0.25))

    static let danger = Color(hex: 0xFF453A)
    static let positive = adaptiveColor(dark: UIColor(hex: 0x30D158), light: UIColor(hex: 0x1A8A3A))
    static let iCloudBlue = Color(hex: 0x2166A0)

    // Condition badge palettes.
    static let badgeGreenText = adaptiveColor(dark: UIColor(hex: 0x4FDD77), light: UIColor(hex: 0x1A8A3A))
    static let badgeGreenFill = Color(hex: 0x30D158, opacity: 0.16)
    static let badgeAmberText = adaptiveColor(dark: UIColor(hex: 0xEB8B3F), light: UIColor(hex: 0xB8560F))
    static let badgeAmberFill = Color(hex: 0xD2691E, opacity: 0.16)
    static let badgeNeutralFill = adaptiveColor(dark: UIColor(white: 1, alpha: 0.10),
                                                light: UIColor(hex: 0x3C3C43, alpha: 0.10))

    // Solid grade colours for the *selected* condition chip. The tinted badge
    // palettes above are for display; when picking a grade the selection has to
    // read unmistakably, so the chip fills with one of these and uses white
    // text (the lower grades previously used grey-on-grey and looked unset).
    static let gradeGreenSolid = adaptiveColor(dark: UIColor(hex: 0x2A9D4F), light: UIColor(hex: 0x1A8A3A))
    static let gradeAmberSolid = adaptiveColor(dark: UIColor(hex: 0xC85D17), light: UIColor(hex: 0xA34E0D))
    static let gradeSlateSolid = adaptiveColor(dark: UIColor(hex: 0x6E6E73), light: UIColor(hex: 0x5A5A5F))
    static let gradeRedSolid = adaptiveColor(dark: UIColor(hex: 0xD03A3F), light: UIColor(hex: 0xB02427))
}

// MARK: - Typography (SF Pro / system font only)

extension Font {
    static let prLargeTitle = Font.system(size: 34, weight: .heavy)   // 34 / 800
    static let prTitle = Font.system(size: 26, weight: .heavy)        // detail title
    static let prTitle2 = Font.system(size: 22, weight: .bold)
    static let prSection = Font.system(size: 20, weight: .bold)       // "Tracklist" / "Notes"
    static let prHeadline = Font.system(size: 17, weight: .semibold)
    static let prBody = Font.system(size: 16)
    static let prBodyEmphasis = Font.system(size: 16, weight: .semibold)
    static let prNav = Font.system(size: 17)                          // nav-bar plain action
    static let prNavBold = Font.system(size: 17, weight: .semibold)
    static let prCaption = Font.system(size: 13, weight: .semibold)   // uppercase section headers
    static let prBadge = Font.system(size: 13, weight: .bold)
    static let prFootnote = Font.system(size: 14)
    static let prSmall = Font.system(size: 13)
}

// MARK: - Metrics

enum Metrics {
    static let screenPadding: CGFloat = 20
    static let cardRadius: CGFloat = 16
    static let smallCardRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 15
    static let tileRadius: CGFloat = 8
    static let badgeRadius: CGFloat = 8
}
