import SwiftUI

/// A small capsule label: PII category tags, plan badges, filter chips, status.
///
/// The app shows a lot of classification — "Aadhaar", "Email", "3 found", "Pro" —
/// and each of those is a chance to invent a new chip. This is the one chip.
/// Its ``Style`` cases are semantic rather than cosmetic (`accent`, not `purple`)
/// so meaning stays attached to colour when the palette is retuned.
public struct Pill: View {

    /// What the pill is saying, not what colour it is.
    public enum Style: Sendable, Equatable {
        /// Neutral metadata — page count, file type.
        case neutral
        /// Brand-significant: Pro, the active filter, the selected rule.
        case accent
        /// Something was found or removed successfully.
        case success
        /// Needs attention — unreviewed detections, a skipped page.
        case warning
    }

    private let text: String
    private let systemImage: String?
    private let style: Style
    /// Spoken instead of `text` when the visual label is an abbreviation.
    private let accessibilityLabelOverride: String?

    public init(
        _ text: String,
        systemImage: String? = nil,
        style: Style = .neutral,
        accessibilityLabel: String? = nil
    ) {
        self.text = text
        self.systemImage = systemImage
        self.style = style
        self.accessibilityLabelOverride = accessibilityLabel
    }

    public var body: some View {
        HStack(spacing: Token.Space.xs / 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .typeStyle(Typography.caption)
        .foregroundStyle(foreground)
        .padding(.horizontal, Token.Space.sm)
        .padding(.vertical, Token.Space.xs)
        .background(Capsule().fill(background))
        .overlay(Capsule().strokeBorder(border, lineWidth: Token.Size.hairlineWidth))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelOverride ?? text)
    }

    private var foreground: Color {
        switch style {
        case .neutral: Token.Text.muted
        case .accent: Token.Accent.violetLight
        case .success: Token.Accent.cyan
        case .warning: Token.Accent.amberLight
        }
    }

    private var background: Color {
        switch style {
        case .neutral: Token.BG.raised.opacity(0.8)
        case .accent: Token.Accent.violet.opacity(Token.Alpha.soft)
        case .success: Token.Accent.cyan.opacity(Token.Alpha.soft)
        case .warning: Token.Accent.amber.opacity(Token.Alpha.soft)
        }
    }

    private var border: Color {
        switch style {
        case .neutral: Token.Line.hairline
        case .accent: Token.Accent.violet.opacity(0.35)
        case .success: Token.Accent.cyan.opacity(0.35)
        case .warning: Token.Accent.amber.opacity(0.35)
        }
    }
}

#Preview("Pill") {
    HStack(spacing: Token.Space.sm) {
        Pill("PDF")
        Pill("Pro", systemImage: "sparkles", style: .accent)
        Pill("Removed", systemImage: "checkmark", style: .success)
        Pill("PAN", style: .warning, accessibilityLabel: "PAN card number")
    }
    .padding(Token.Space.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ambientBackground()
    .preferredColorScheme(.dark)
}
