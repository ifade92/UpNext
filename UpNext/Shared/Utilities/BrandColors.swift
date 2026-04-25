//
//  BrandColors.swift
//  UpNext
//
//  Single source of truth for all UpNext brand colors.
//  Every color in the app should come from here — never hardcode hex values in views.
//
//  Brand Kit v2.0 — March 2026
//

import SwiftUI

// MARK: - Color Extensions

extension Color {

    // ── Primary Palette ──────────────────────────────────────────

    /// #0D2B1A — Deep green. Primary background for all screens.
    static let brandBackground = Color(hex: "0D2B1A")

    /// #2ECC71 — Bright accent green. CTAs, active states, Go Live toggle, highlights.
    static let accent = Color(hex: "2ECC71")

    /// #1BA355 — Darker green. Used for pressed/active states on accent elements.
    static let accentDark = Color(hex: "1BA355")

    /// #8BA898 — Grey-green. Secondary text, muted labels, the "Next" wordmark tint.
    static let brandSecondary = Color(hex: "8BA898")

    /// #0D0D0D — Near black. Alternate background, used for cards on deep green bg.
    static let brandNearBlack = Color(hex: "0D0D0D")

    // ── UI Surface Colors ────────────────────────────────────────

    /// Slightly lighter than the main bg — used for cards and elevated surfaces.
    static let brandSurface = Color(hex: "142E1D")

    /// Even lighter surface — used for list rows and secondary cards.
    static let brandSurfaceAlt = Color(hex: "1A3A24")

    /// The dot mark background — used in logo and icon mark.
    static let brandDotBg = Color(hex: "2A4A35")

    /// Input field background — neutral dark grey (Apple's iOS dark mode standard).
    /// Intentionally not green so fields feel distinct and native on the near-black bg.
    static let brandInput = Color(hex: "1C1C1E")

    /// Slightly lighter than brandInput — used for list rows inside cards so they
    /// have a subtle visual hierarchy against the card background.
    static let brandInputAlt = Color(hex: "242426")

    // ── Text Colors ──────────────────────────────────────────────

    /// Primary text — white.
    static let brandTextPrimary = Color.white

    /// Secondary text — grey-green, softer than white.
    static let brandTextSecondary = Color(hex: "8BA898")

    /// Muted text — for timestamps, labels, captions.
    static let brandTextMuted = Color.white.opacity(0.3)
}

// MARK: - UpNext Dot Mark

/// The three-shape brand mark — circle, wide bar, short bar — used everywhere
/// the scissors icon used to be. Pass a `size` to scale it up or down.
struct UpNextMark: View {
    var size: CGFloat = 24  // Controls the overall scale of the mark

    private var dot: CGFloat   { size * 0.35 }
    private var wide: CGFloat  { size }
    private var short: CGFloat { size * 0.58 }
    private var bar: CGFloat   { size * 0.27 }
    private var gap: CGFloat   { size * 0.22 }
    private var radius: CGFloat { bar * 0.35 }

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            Circle()
                .fill(Color.accent.opacity(0.6))
                .frame(width: dot, height: dot)
            RoundedRectangle(cornerRadius: radius)
                .fill(Color.accent)
                .frame(width: wide, height: bar)
            RoundedRectangle(cornerRadius: radius)
                .fill(Color.accent.opacity(0.6))
                .frame(width: short, height: bar)
        }
    }
}

// MARK: - Brand Typography

extension Font {
    // Outfit-Bold — use for all headings, titles, and prominent labels
    static let brandLargeTitle  = Font.custom("Outfit-Bold",    size: 34)
    static let brandTitle       = Font.custom("Outfit-Bold",    size: 28)
    static let brandTitle2      = Font.custom("Outfit-Bold",    size: 22)
    static let brandHeadline    = Font.custom("Outfit-Bold",    size: 18)

    // Outfit-Regular — use for subheadings and descriptive text
    static let brandSubheadline = Font.custom("Outfit-Regular", size: 15)
    static let brandBody        = Font.custom("Outfit-Regular", size: 17)
    static let brandCaption     = Font.custom("Outfit-Regular", size: 13)
}

// MARK: - Hex Color Initializer

extension Color {
    /// Initialize a Color from a hex string (with or without #).
    /// Example: Color(hex: "2ECC71") or Color(hex: "#2ECC71")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b, a: UInt64
        switch hex.count {
        case 3:  // RGB shorthand (e.g. "03F")
            (r, g, b, a) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17, 255)
        case 6:  // RGB full (e.g. "0033FF")
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8:  // RGBA full (e.g. "0033FFAA")
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }

        self.init(
            .sRGB,
            red:     Double(r) / 255,
            green:   Double(g) / 255,
            blue:    Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
