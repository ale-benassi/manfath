import AppKit
import SwiftUI

/// Design tokens for the Manfath popover. The dark palette matches the website.
enum Theme {
    static let bg0          = color(light: 0xFFFFFF, dark: 0x0A0A0C)
    static let bg1          = color(light: 0xFAF9F5, dark: 0x101014)
    static let bg2          = color(light: 0xF6F4EE, dark: 0x16161B)
    static let surfaceHi    = color(light: 0xFCFBF8, dark: 0x1A1A1F)
    static let surfaceLo    = color(light: 0xF2F0E9, dark: 0x141418)
    static let chromeShade = color(light: 0xB6B9B0, dark: 0x000000)

    static let ink       = color(light: 0x272620, dark: 0xE8E4DA)
    static let inkDim    = color(light: 0x514E45, dark: 0x9A958A)
    static let inkFaint  = color(light: 0x646055, dark: 0x5A564E)

    static let line       = ink.opacity(0.08)
    static let lineStrong = ink.opacity(0.16)
    static let hoverFill  = ink.opacity(0.13)
    static let hoverEdge  = ink.opacity(0.38)

    static let amber     = color(light: 0x376612, dark: 0xB8FF5C)
    static let amberSoft = color(light: 0x477820, dark: 0x8FC840)
    static let cyan      = color(light: 0x006E84, dark: 0x5CE4FF)
    static let danger    = color(light: 0xAE3030, dark: 0xFF7A7A)
    static let onDanger  = color(light: 0xFFFFFF, dark: 0x16161B)

    static let popoverGradient = LinearGradient(
        colors: [surfaceHi, surfaceLo],
        startPoint: .top,
        endPoint: .bottom
    )

    static let mono     = Font.system(.body, design: .monospaced)
    static let monoSize: (CGFloat) -> Font = { size in
        .system(size: size, design: .monospaced)
    }

    private static func color(light: UInt32, dark: UInt32) -> Color {
        let lightColor = rgb(light)
        let darkColor = rgb(dark)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        })
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum HoverFeedbackStyle {
    case fill, outline
}

extension View {
    /// Adds feedback to the existing control bounds without changing its style or hit area.
    func hoverFeedback(
        _ style: HoverFeedbackStyle = .fill,
        radius: CGFloat = 4,
        outset: CGFloat = 0
    ) -> some View {
        modifier(HoverFeedback(style: style, radius: radius, outset: outset))
    }
}

private struct HoverFeedback: ViewModifier {
    let style: HoverFeedbackStyle
    let radius: CGFloat
    let outset: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        let visible = isEnabled && isHovered

        content
            .onHover { isHovered = $0 }
            .background {
                if visible, style == .fill {
                    shape.fill(Theme.hoverFill)
                        .padding(-outset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if visible, style == .outline {
                    shape.strokeBorder(Theme.hoverEdge, lineWidth: 1)
                        .padding(-outset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}
