import SwiftUI

/// The first-run explainer. Three screens, skippable from the first frame, ending in the sample
/// document.
///
/// The content is chosen to answer the one question that decides whether this app is worth
/// installing: *why is this different from drawing a black box in Markup?* Screen two says the
/// quiet part out loud — most black boxes are a layer over text that is still there, and ours is
/// not. Screen three proves it on a real document without asking for a camera, a photo, or an
/// account, which is also exactly what an App Review VM can do.
struct OnboardingView: View {

    /// Runs the bundled sample through the real pipeline and opens the editor.
    let onTrySample: () -> Void
    /// Dismisses to the home screen without running anything.
    let onSkip: () -> Void

    @Environment(\.accessibleAnimation) private var accessibleAnimation
    @State private var pageIndex = 0

    private var pages: [Page] { Page.all }

    var body: some View {
        VStack(spacing: 0) {
            skipBar

            TabView(selection: $pageIndex) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    pageBody(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            pageIndicator
                .padding(.bottom, Token.Space.md)

            actions
                .padding(.horizontal, Token.Space.lg)
                .padding(.bottom, Token.Space.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ambientBackground()
        .preferredColorScheme(.dark)
    }

    // MARK: - Bars

    private var skipBar: some View {
        HStack {
            Spacer()
            Button(action: onSkip) {
                Text("Skip")
                    .typeStyle(Typography.label)
                    .foregroundStyle(Token.Text.muted)
                    .frame(minWidth: Token.Size.minimumHitTarget, minHeight: Token.Size.minimumHitTarget)
                    .padding(.horizontal, Token.Space.sm)
            }
            .accessibilityLabel("Skip the introduction")
            .accessibilityHint("Goes straight to the home screen")
        }
        .padding(.trailing, Token.Space.sm)
    }

    /// A hand-built indicator rather than `.page`'s dots: the built-in one is decorative to
    /// VoiceOver but still focusable, and it cannot be tinted from tokens.
    private var pageIndicator: some View {
        HStack(spacing: Token.Space.xs) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == pageIndex ? AnyShapeStyle(Token.gradient) : AnyShapeStyle(Token.Line.strong))
                    .frame(width: index == pageIndex ? Token.Space.md : Token.Space.xs, height: Token.Space.xs)
            }
        }
        .accessibleAnimation(Motion.snappy, value: pageIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(pageIndex + 1) of \(pages.count)")
    }

    // MARK: - Page content

    private func pageBody(_ page: Page) -> some View {
        ScrollView {
            VStack(spacing: Token.Space.lg) {
                Spacer(minLength: Token.Space.lg)

                IconWell(page.symbol, size: Token.Size.mark, tint: .gradient)

                VStack(spacing: Token.Space.sm) {
                    Text(page.title)
                        .typeStyle(Typography.displayLarge)
                        .foregroundStyle(Token.Text.primary)
                        .multilineTextAlignment(.center)

                    Text(page.body)
                        .typeStyle(Typography.body)
                        .foregroundStyle(Token.Text.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: Token.Layout.proseWidth)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                if let proof = page.proof {
                    proofCard(proof)
                }

                Spacer(minLength: Token.Space.lg)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Token.Space.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func proofCard(_ points: [Proof]) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            ForEach(points, id: \.text) { point in
                HStack(alignment: .top, spacing: Token.Space.sm) {
                    Image(systemName: point.isGood ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .typeStyle(Typography.bodyEmphasis)
                        .foregroundStyle(point.isGood ? Token.Accent.cyan : Token.Text.faint)
                        .accessibilityHidden(true)

                    Text(point.text)
                        .typeStyle(Typography.callout)
                        .foregroundStyle(point.isGood ? Token.Text.primary : Token.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(point.isGood ? "Redact: \(point.text)" : "Other tools: \(point.text)")
            }
        }
        .frame(maxWidth: Token.Layout.proseWidth)
        .glassCard()
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if pageIndex == pages.count - 1 {
            VStack(spacing: Token.Space.sm) {
                PrimaryButton("Try it on a sample document", systemImage: "wand.and.sparkles", action: onTrySample)

                Text(SampleDocument.subtitle)
                    .typeStyle(Typography.caption)
                    .foregroundStyle(Token.Text.faint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                SecondaryButton("Go to the home screen", prominence: .plain, action: onSkip)
            }
        } else {
            PrimaryButton("Continue") {
                withAnimation(accessibleAnimation(Motion.standard)) {
                    pageIndex = min(pageIndex + 1, pages.count - 1)
                }
            }
        }
    }

    // MARK: - Copy

    private struct Proof {
        let text: String
        let isGood: Bool
    }

    private struct Page {
        let symbol: String
        let title: String
        let body: String
        var proof: [Proof]?

        static let all: [Page] = [
            Page(
                symbol: "doc.text.viewfinder",
                title: "It finds what you'd miss",
                body: """
                Point Redact at a payslip, an invoice or an ID card and it reads the page on your \
                device, then marks the Aadhaar numbers, PAN, phone numbers, email addresses and \
                names it finds. You decide what actually gets removed.
                """
            ),
            Page(
                symbol: "lock.doc.fill",
                title: "A black box is not redaction",
                body: """
                Most apps draw a rectangle on top of the text. The text is still in the file, and \
                anyone can select it, copy it, or lift the shape off in a PDF reader.
                """,
                proof: [
                    Proof(text: "A shape is drawn over the words, which stay in the file underneath", isGood: false),
                    Proof(text: "Redact destroys the pixels and rebuilds the file, so there is nothing left to recover", isGood: true),
                    Proof(text: "Location, camera and edit history are stripped out with it", isGood: true)
                ]
            ),
            Page(
                symbol: "iphone.gen3",
                title: "Nothing leaves this iPhone",
                body: """
                There is no account, no upload and no server. Redact makes no network connections \
                at all, which is why we can honestly tell Apple we collect no data. Try it now on a \
                document we made up, so you can see it work before you trust it with your own.
                """
            )
        ]
    }
}

#Preview("Onboarding") {
    OnboardingView(onTrySample: {}, onSkip: {})
}
