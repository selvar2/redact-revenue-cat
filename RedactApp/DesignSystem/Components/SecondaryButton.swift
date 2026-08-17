import SwiftUI

/// The alternative action beside a ``PrimaryButton`` — glass, not gradient.
///
/// It exists so that "the other button" has exactly one look. Left to improvise,
/// feature agents produce bordered buttons, tinted buttons, and plain text links
/// on three different screens for the same semantic role, and the app stops
/// looking designed. Visual weight is deliberately well below primary so the
/// hierarchy survives even when both are on screen.
public struct SecondaryButton: View {

    /// How much visual weight the button carries.
    public enum Prominence: Sendable, Equatable {
        /// Glass surface with a hairline border — the default alternative action.
        case glass
        /// Text and glyph only. For tertiary actions such as "Restore Purchases",
        /// where a third filled rectangle would crowd the layout.
        case plain
    }

    private let title: String
    private let systemImage: String?
    private let prominence: Prominence
    private let role: ButtonRole?
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: String,
        systemImage: String? = nil,
        prominence: Prominence = .glass,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.prominence = prominence
        self.role = role
        self.action = action
    }

    public var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: Token.Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .typeStyle(Typography.label)
            .foregroundStyle(foreground)
            .frame(maxWidth: prominence == .glass ? .infinity : nil)
            .frame(minHeight: Token.Size.minimumHitTarget)
            .padding(.horizontal, Token.Space.md)
        }
        .buttonStyle(SecondaryButtonStyle(prominence: prominence))
        .opacity(isEnabled ? 1 : Token.Alpha.disabled)
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        role == .destructive ? Token.Accent.amberLight : Token.Text.primary
    }
}

/// Press behaviour and surface for ``SecondaryButton``.
public struct SecondaryButtonStyle: ButtonStyle {

    private let prominence: SecondaryButton.Prominence

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(prominence: SecondaryButton.Prominence = .glass) {
        self.prominence = prominence
    }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .background(surface(pressed: pressed))
            .opacity(prominence == .plain && pressed ? 0.6 : 1)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(Motion.accessible(Motion.snappy, reduceMotion: reduceMotion), value: pressed)
    }

    @ViewBuilder
    private func surface(pressed: Bool) -> some View {
        switch prominence {
        case .glass:
            ZStack {
                RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous)
                    .fill(pressed ? Token.BG.raised : Token.BG.card.opacity(Token.Alpha.glassTint))
                    .background(.ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: Token.Radius.control,
                                                     style: .continuous))
                RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Token.Line.strong, Token.Line.hairline],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: Token.Size.hairlineWidth
                    )
            }
        case .plain:
            Color.clear
        }
    }
}

#Preview("SecondaryButton") {
    VStack(spacing: Token.Space.md) {
        SecondaryButton("Choose from Photos", systemImage: "photo.on.rectangle") {}
        SecondaryButton("Restore Purchases", prominence: .plain) {}
        SecondaryButton("Delete original", systemImage: "trash", role: .destructive) {}
    }
    .padding(Token.Space.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ambientBackground()
    .preferredColorScheme(.dark)
}
