import SwiftUI

/// About and legal.
///
/// Two jobs. First, it is where the Privacy Policy and Terms of Use live for users who go looking —
/// App Review checks that both are reachable and that neither is a dead link. Second, it states in
/// plain language what "on-device" actually means here, because a privacy claim nobody can check is
/// worth nothing; every line below is a statement a reader could verify by putting the phone in
/// aeroplane mode.
struct AboutView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let onboarding: OnboardingState

    init(onboarding: OnboardingState = .shared) {
        self.onboarding = onboarding
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Token.Space.lg) {
                protections
                legal
                version
            }
            .padding(.horizontal, Token.Space.lg)
            .padding(.vertical, Token.Space.md)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity)
        .ambientBackground(.subdued)
        .navigationTitle("About Redact")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .accessibilityLabel("Close about")
            }
        }
    }

    // MARK: - How Redact protects you

    private var protections: some View {
        VStack(alignment: .leading, spacing: Token.Space.md) {
            SectionHeader(
                "How Redact protects you",
                overline: "Privacy",
                subtitle: "Four things this app does differently, all of which you can check yourself."
            )

            ForEach(Protection.all, id: \.title) { item in
                HStack(alignment: .top, spacing: Token.Space.sm) {
                    IconWell(item.symbol, tint: .gradient)

                    VStack(alignment: .leading, spacing: Token.Space.xs) {
                        Text(item.title)
                            .typeStyle(Typography.bodyEmphasis)
                            .foregroundStyle(Token.Text.primary)
                        Text(item.detail)
                            .typeStyle(Typography.callout)
                            .foregroundStyle(Token.Text.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.title). \(item.detail)")
            }
        }
        .glassCard()
    }

    // MARK: - Legal

    private var legal: some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            SectionHeader("Legal", overline: "Documents")

            link("Privacy Policy", symbol: "hand.raised.fill", url: LegalLinks.privacyPolicy)
            link("Terms of Use", symbol: "doc.plaintext.fill", url: LegalLinks.termsOfUse)
            link("Support", symbol: "questionmark.circle.fill", url: LegalLinks.support)

            Text("These pages open in Safari. Redact itself never connects to the internet.")
                .typeStyle(Typography.caption)
                .foregroundStyle(Token.Text.faint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Token.Space.xs)

            SecondaryButton("Show the introduction again", systemImage: "arrow.counterclockwise", prominence: .plain) {
                onboarding.reset()
                dismiss()
            }
            .padding(.top, Token.Space.xs)
        }
        .glassCard()
    }

    private func link(_ title: String, symbol: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: Token.Space.sm) {
                Image(systemName: symbol)
                    .typeStyle(Typography.body)
                    .foregroundStyle(Token.Accent.violetLight)
                    .accessibilityHidden(true)

                Text(title)
                    .typeStyle(Typography.label)
                    .foregroundStyle(Token.Text.primary)

                Spacer(minLength: Token.Space.xs)

                Image(systemName: "arrow.up.right")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(Token.Text.faint)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Token.Size.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Opens in Safari")
        .accessibilityAddTraits(.isLink)
    }

    // MARK: - Version

    private var version: some View {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        return Text("Redact \(short) (\(build))")
            .typeStyle(Typography.caption)
            .foregroundStyle(Token.Text.faint)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("Redact version \(short), build \(build)")
    }

    // MARK: - Copy

    private struct Protection {
        let symbol: String
        let title: String
        let detail: String

        static let all: [Protection] = [
            Protection(
                symbol: "wifi.slash",
                title: "No network, at all",
                detail: """
                Redact makes zero network requests. Turn on aeroplane mode and every feature still \
                works exactly the same, because there was never anything on the other end.
                """
            ),
            Protection(
                symbol: "eraser.fill",
                title: "Removal, not cover-up",
                detail: """
                Covered areas are erased from the image data and the file is rebuilt from scratch. \
                There is no layer to peel back and no text hiding under the bar.
                """
            ),
            Protection(
                symbol: "camera.metering.none",
                title: "Hidden data stripped too",
                detail: """
                Location, camera model, timestamps and embedded thumbnails are removed from what \
                you export. A photo can give away where you were even after the words are gone.
                """
            ),
            Protection(
                symbol: "externaldrive.badge.xmark",
                title: "Nothing is collected",
                detail: """
                No account, no analytics, no crash reporting. Your documents stay in this app's \
                storage, excluded from backups, and deleting a document deletes its files.
                """
            )
        ]
    }
}

#Preview("About") {
    NavigationStack {
        AboutView()
    }
    .preferredColorScheme(.dark)
}
