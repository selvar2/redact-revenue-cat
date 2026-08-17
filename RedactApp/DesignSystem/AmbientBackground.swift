import SwiftUI

/// The app's ambient background: the base navy ramp under two slowly drifting
/// radial glows, one violet and one amber.
///
/// Extracted from `RootView` because it belongs on *every* full-screen surface —
/// scan, editor, export, paywall. Duplicating the glow geometry per screen is how
/// the drift ends up out of phase between screens and the app stops feeling like
/// one continuous space, which is exactly the cohesion a design award is judged on.
///
/// It is decorative by definition, so the whole thing is hidden from VoiceOver.
public struct AmbientBackground: View {

    /// How assertive the glow is.
    ///
    /// Content-heavy screens (the editor, where a document must stay legible)
    /// need the glow pulled back; the launch and paywall screens want it full.
    public enum Intensity: Sendable, Equatable {
        case full
        case subdued

        var violetOpacity: Double {
            switch self {
            case .full: 0.22
            case .subdued: 0.10
            }
        }

        var amberOpacity: Double {
            switch self {
            case .full: 0.18
            case .subdued: 0.08
            }
        }
    }

    private let intensity: Intensity

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    public init(intensity: Intensity = .full) {
        self.intensity = intensity
    }

    public var body: some View {
        ZStack {
            Token.BG.base

            glow(
                color: Token.Accent.violet.opacity(intensity.violetOpacity),
                center: .init(x: 0.18, y: 0.22),
                radius: 420
            )
            glow(
                color: Token.Accent.amber.opacity(intensity.amberOpacity),
                center: .init(x: 0.84, y: 0.78),
                radius: 400
            )
        }
        .ignoresSafeArea()
        .scaleEffect(drift ? 1.06 : 1.0)
        .offset(x: drift ? 14 : -12, y: drift ? 10 : -8)
        .onAppear {
            // Reduced motion gets a static field rather than a 16s drift loop.
            // A cross-fade is meaningless for a background that never changes
            // state, so here the correct degradation is simply no movement.
            guard !reduceMotion else { return }
            withAnimation(Motion.ambientDrift) { drift = true }
        }
        .accessibilityHidden(true)
    }

    private func glow(color: Color, center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(colors: [color, .clear], center: center, startRadius: 0, endRadius: radius)
    }
}

public extension View {
    /// Places the shared ambient field behind this view.
    ///
    /// The idiomatic way to open a full-screen feature view.
    func ambientBackground(_ intensity: AmbientBackground.Intensity = .full) -> some View {
        background(AmbientBackground(intensity: intensity))
    }
}

#Preview("Ambient background") {
    VStack(spacing: Token.Space.md) {
        Text("Full").typeStyle(Typography.title)
        Text("Subdued behind content").typeStyle(Typography.callout)
    }
    .foregroundStyle(Token.Text.primary)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ambientBackground()
    .preferredColorScheme(.dark)
}
