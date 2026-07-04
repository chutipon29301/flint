import SwiftUI

// MARK: - DesignSystem
//
// Single source of truth for Flint's visual language: color, type, radius, and
// spacing tokens. These mirror the landing page's CSS `:root` palette
// (docs/index.html) so the native app and the website read as one continuous
// product — same graphite base, same ember accent used with the same
// restraint, same code-syntax colors, same type personality.
//
// Dark-only for v1 — this is an intentional choice (the popover is dark by
// design). When light mode is added, define a parallel light token set here
// so it becomes a token swap, not a rewrite. Never hard-code colors in views;
// always read through `Color.*` / `Font.*` / `Radius.*` tokens defined below.

// MARK: - Color hex initializer

extension Color {
    /// Creates a Color from a packed 24-bit hex value, e.g. `Color(hex: 0x14171c)`.
    init(hex: UInt, alpha: Double = 1) {
        let red = Double((hex & 0xFF0000) >> 16) / 255.0
        let green = Double((hex & 0x00FF00) >> 8) / 255.0
        let blue = Double(hex & 0x0000FF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - Palette tokens

extension Color {
    // Graphite scale — cool, disciplined base.
    static let graphite950 = Color(hex: 0x14171c) // app/popover background (NOT pure black)
    static let graphite925 = Color(hex: 0x171b21)
    static let graphite900 = Color(hex: 0x1a1e24) // cards, raised surfaces, detail panels
    static let graphite850 = Color(hex: 0x1f242b) // hover / pressed surface
    static let graphite800 = Color(hex: 0x242a32) // borders, dividers
    static let graphite700 = Color(hex: 0x333b45) // stronger borders, kbd chips

    // Text scale.
    static let ash = Color(hex: 0x8a94a2)    // secondary/muted text, inactive icons
    static let ashDim = Color(hex: 0x626b78) // tertiary text, captions, placeholders
    static let chalk = Color(hex: 0xe8ebef)  // primary text (cool white)

    // The ember accent — a scalpel, not a bucket. Primary action, active/selected
    // tool, detection banner, focus rings, and the single most important syntax
    // token ONLY. Never a large fill.
    static let spark = Color(hex: 0xff7a1a)
    static let sparkHot = Color(hex: 0xffb347) // ember highlight / hover of accent, key syntax token
    static let sparkGlow = Color(hex: 0xff7a1a, alpha: 0.14)

    // Syntax-highlighting tokens (JSON / JWT / code views).
    static let codeKey = Color(hex: 0xffb347)    // JSON keys, JWT claim names (== sparkHot)
    static let codeString = Color(hex: 0x6fd3b8) // string values (== site's --jade; reuse for success/valid)
    static let codeNumber = Color(hex: 0xc9a8ff) // numbers, booleans, timestamps
    static let codePunct = Color(hex: 0x626b78)  // braces, brackets, colons, commas (== ashDim)

    // Semantic states — palette-harmonized, desaturated, and deliberately
    // distinct from `spark` so the accent stays special.
    static let errorText = Color(hex: 0xe5657f)
    static let errorFill = Color(hex: 0xe5657f, alpha: 0.10)
    static let errorBorder = Color(hex: 0xe5657f, alpha: 0.28)

    static let warningText = Color(hex: 0xd9a441)
    static let warningFill = Color(hex: 0xd9a441, alpha: 0.10)
    static let warningBorder = Color(hex: 0xd9a441, alpha: 0.28)

    /// Success / valid state — reuses the jade `codeString` token.
    static let success = codeString
}

// MARK: - Typography

extension Font {
    /// Uppercase-intent section labels (11pt, semibold, mono).
    static let monoLabel = Font.system(size: 11, weight: .semibold, design: .monospaced)
    /// Code / data body copy (13pt, mono).
    static let monoBody = Font.system(size: 13, design: .monospaced)
    /// Search field input (15pt, mono).
    static let monoSearch = Font.system(size: 15, design: .monospaced)
    /// Default-design body prose (13pt).
    static let bodyText = Font.system(size: 13)
    /// Tool title in lists/grids (14pt, semibold, default design).
    static let toolTitle = Font.system(size: 14, weight: .semibold)
    /// Detail screen heading (16pt, semibold, default design).
    static let detailHeading = Font.system(size: 16, weight: .semibold)
}

// MARK: - Radius & spacing

/// Corner radius tokens mirroring the site's card/control/chip scale.
enum Radius {
    static let card: CGFloat = 11
    static let control: CGFloat = 8
    static let chip: CGFloat = 5
}

/// Common spacing tokens — kept minimal; most views can use SwiftUI's default
/// stack spacing and only reach for these where the brief calls out a
/// specific value.
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
}

// MARK: - PrimaryButtonStyle

/// The ONE spark-filled button per screen — the primary action (brief: "the ember
/// accent is a scalpel, not a bucket"). Mirrors DetectionBannerView's "Open" button:
/// spark fill, graphite950 label, `Radius.control` corners. Hover brightens to
/// `sparkHot` (no-op under Reduce Motion); pressed state dims slightly.
///
/// Apply only to a screen's single primary action (e.g. "Generate", "Get Started").
/// Everything else stays greyscale — use the system `.bordered` style or `.plain`.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.graphite950)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(fillColor(pressed: configuration.isPressed))
            )
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { hovering in
                if reduceMotion {
                    isHovered = hovering
                } else {
                    withAnimation(.easeOut(duration: 0.1)) {
                        isHovered = hovering
                    }
                }
            }
    }

    private func fillColor(pressed: Bool) -> Color {
        if pressed {
            return Color.spark.opacity(0.85)
        }
        return isHovered ? Color.sparkHot : Color.spark
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    /// The single spark-filled primary action button for a screen.
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
