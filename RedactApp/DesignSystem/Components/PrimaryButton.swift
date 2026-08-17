import SwiftUI

/// The app's single primary call to action: gradient-filled, one per screen.
///
/// It exists as a component rather than a style so the three things that are
/// easy to get wrong are impossible to omit — the 44pt minimum hit target, the
/// reduced-motion-aware press response, and the fact that a button carrying only
/// an icon still needs a spoken label. Feature agents supplying a title get all
/// three for free.
///
/// Scarcity is part of the design: if two of these appear on one screen, neither
/// reads as primary. Use ``SecondaryButton`` for the alternative action.
public struct PrimaryButton: View {

    private let title: String
    private let systemImage: String?
    private let isLoading: Bool
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    /// - Parameters:
    ///   - title: the spoken and displayed label. Never a placeholder
    ///     (`CLAUDE.md` rule 10) — write the real verb.
    ///   - systemImage: optional leading SF Symbol, decorative only.
    ///   - isLoading: replaces the glyph with a spinner and blocks the action,
    ///     so callers never need to disable-and-overlay by hand.
    public init(
        _ title: String,
        systemImage: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Token.Space.xs) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .typeStyle(Typography.label)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Token.Size.minimumHitTarget)
            .padding(.horizontal, Token.Space.md)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isLoading)
        .opacity(isEnabled ? 1 : Token.Alpha.disabled)
        .accessibilityLabel(isLoading ? "\(title). Working." : title)
    }
}

/// The gradient fill and press behaviour, split out so the visual treatment can
/// also be applied to a `Button` that needs custom content.
public struct PrimaryButtonStyle: ButtonStyle {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .background(
                RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous)
                    .fill(Token.gradient)
            )
            .overlay(
                // A top-edge white ramp reads as light catching the button's
                // bevel; without it the flat gradient looks printed on.
                RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: Token.Size.hairlineWidth
                    )
            )
            .shadow(pressed ? Token.Shadow.pressed : Token.Shadow.glow)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(Motion.accessible(Motion.snappy, reduceMotion: reduceMotion), value: pressed)
    }
}

#Preview("PrimaryButton") {
    VStack(spacing: Token.Space.md) {
        PrimaryButton("Scan a document", systemImage: "doc.viewfinder") {}
        PrimaryButton("Redacting", isLoading: true) {}
        PrimaryButton("Unavailable") {}.disabled(true)
    }
    .padding(Token.Space.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ambientBackground()
    .preferredColorScheme(.dark)
}
