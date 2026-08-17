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
    /// The mark grows with the user's text size so it stays in proportion to the
    /// wordmark beneath it at Larger Accessibility Sizes (CLAUDE.md rule 4).
    @ScaledMetric(relativeTo: .largeTitle) private var markSize = Token.Size.mark
    #if DEBUG
    @State private var showingTokenGallery = false
    #endif

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
        #if DEBUG
        // Debug-only entry to the token gallery, so the simulator run in verify.sh
        // can actually reach it. F02's "token gallery renders" criterion is
        // otherwise satisfied only in the Xcode canvas. Compiled out of Release,
        // so it adds no user-visible surface (CLAUDE.md rule 10).
        .overlay(alignment: .topTrailing) {
            Button {
                showingTokenGallery = true
            } label: {
                Image(systemName: "paintpalette.fill")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(Token.Text.faint)
                    .frame(width: Token.Size.minimumHitTarget, height: Token.Size.minimumHitTarget)
            }
            .accessibilityLabel("Open design token gallery")
            .padding(.trailing, Token.Space.sm)
        }
        .sheet(isPresented: $showingTokenGallery) {
            TokenGallery()
        }
        #endif
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
                colors: [Token.Accent.violet.opacity(Token.Alpha.glowPrimary), .clear],
                center: .init(x: 0.18, y: 0.22),
                startRadius: 0,
                endRadius: 420
            )
            RadialGradient(
                colors: [Token.Accent.amber.opacity(Token.Alpha.glowSecondary), .clear],
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
            .frame(width: markSize, height: markSize)
            .overlay(
                Image(systemName: "eye.slash.fill")
                    .typeStyle(Typography.markGlyph)
                    .foregroundStyle(.white)
            )
            .shadow(Token.Shadow.mark)
            .accessibilityHidden(true)
    }

    private var headline: some View {
        VStack(spacing: Token.Space.sm) {
            Text("Redact")
                .typeStyle(Typography.displayXL)
                .foregroundStyle(Token.Text.primary)

            Text("Find personal information in any document and remove it permanently.")
                .typeStyle(Typography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Token.Text.muted)
                .frame(maxWidth: Token.Layout.proseWidth)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Redact. Find personal information in any document and remove it permanently.")
    }

    /// The product's central promise, stated on the first screen because it is the
    /// reason to trust the app — and because it is literally true (DEC-004).
    private var privacyNote: some View {
        HStack(spacing: Token.Space.xs) {
            Image(systemName: "lock.fill")
                .typeStyle(Typography.caption)
            Text("Everything happens on this device")
                .typeStyle(Typography.caption)
        }
        .foregroundStyle(Token.Text.faint)
        .padding(.horizontal, Token.Space.md)
        .padding(.vertical, Token.Space.sm)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule().strokeBorder(Token.Line.hairline, lineWidth: Token.Size.hairlineWidth)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Everything happens on this device. Nothing is uploaded.")
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}
