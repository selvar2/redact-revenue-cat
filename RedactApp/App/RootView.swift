import SwiftUI

/// The app's first screen.
///
/// Phase 0 deliberately ships a *real* screen rather than a placeholder: the
/// scaffold's acceptance criterion (F01) is that the app launches showing genuine
/// UI, and `CLAUDE.md` rule 10 forbids placeholder content anywhere. The scan
/// action is wired to real navigation in Phase 2 (F06).
struct RootView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ambientDrift = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: Token.Space.lg) {
                Spacer()
                mark
                headline
                Spacer()
                privacyNote
            }
            .padding(.horizontal, Token.Space.lg)
            .padding(.bottom, Token.Space.xl)
        }
        .onAppear {
            // reduceMotion callers get a static background rather than a drift
            // loop — CLAUDE.md rule 4.
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                ambientDrift = true
            }
        }
    }

    // MARK: - Background

    /// Ambient radial glows over the base ramp, mirroring the source HTML's
    /// `.hero-glow` layer (DEC-002).
    private var background: some View {
        ZStack {
            Token.BG.base

            RadialGradient(
                colors: [Token.Accent.violet.opacity(0.22), .clear],
                center: .init(x: 0.18, y: 0.22),
                startRadius: 0,
                endRadius: 420
            )
            RadialGradient(
                colors: [Token.Accent.amber.opacity(0.18), .clear],
                center: .init(x: 0.84, y: 0.78),
                startRadius: 0,
                endRadius: 400
            )
        }
        .ignoresSafeArea()
        .scaleEffect(ambientDrift ? 1.06 : 1.0)
        .offset(x: ambientDrift ? 14 : -12, y: ambientDrift ? 10 : -8)
        .accessibilityHidden(true)
    }

    // MARK: - Content

    private var mark: some View {
        RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous)
            .fill(Token.gradient)
            .frame(width: 72, height: 72)
            .overlay(
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: Token.Accent.violet.opacity(0.5), radius: 28, y: 10)
            .accessibilityHidden(true)
    }

    private var headline: some View {
        VStack(spacing: Token.Space.sm) {
            Text("Redact")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(Token.Text.primary)

            Text("Find personal information in any document and remove it permanently.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Token.Text.muted)
                .frame(maxWidth: 320)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Redact. Find personal information in any document and remove it permanently.")
    }

    /// The product's central promise, stated on the first screen because it is the
    /// reason to trust the app — and because it is literally true (DEC-004).
    private var privacyNote: some View {
        HStack(spacing: Token.Space.xs) {
            Image(systemName: "lock.fill")
                .font(.caption2)
            Text("Everything happens on this device")
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(Token.Text.faint)
        .padding(.horizontal, Token.Space.md)
        .padding(.vertical, Token.Space.sm)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule().strokeBorder(Token.Line.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Everything happens on this device. Nothing is uploaded.")
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}
