import RevenueCat
import SwiftUI

/// The block App Review looks for, rendered identically under **both** paywall paths.
///
/// Restore Purchases, the Terms of Use (EULA) link, the Privacy Policy link and the auto-renewal
/// sentence are all documented rejection causes when missing. A remote paywall designed in the
/// RevenueCat dashboard *can* carry all four — but whether it does depends on a dashboard
/// configuration that can be edited after this app ships. Rendering our own footer underneath means
/// the compliant version is the one that is compiled in, and a dashboard mistake can only ever add a
/// second restore button, never remove the only one.
///
/// The terms sentence is the string that must never be truncated: it uses
/// `.fixedSize(horizontal: false, vertical: true)` and no line limit, so it grows down the screen at
/// accessibility text sizes instead of clipping.
struct PaywallLegalFooter: View {

    /// The package whose price and period the disclosure describes — the one the primary button
    /// would buy. Passing `nil` (no plans loaded) drops the price sentence rather than inventing one.
    let package: Package?
    let isRestoring: Bool
    let restore: () -> Void

    var body: some View {
        VStack(spacing: Token.Space.sm) {
            SecondaryButton(
                String(localized: "Restore Purchases", comment: "Button: restore previously bought subscriptions"),
                systemImage: "arrow.clockwise",
                prominence: .glass,
                action: restore
            )
            .disabled(isRestoring)
            .accessibilityHint(String(
                localized: "Checks your Apple Account for a Redact Pro purchase you have already made.",
                comment: "VoiceOver hint on Restore Purchases"
            ))
            .overlay(alignment: .trailing) {
                if isRestoring {
                    ProgressView()
                        .padding(.trailing, Token.Space.sm)
                        .accessibilityLabel(String(localized: "Restoring", comment: "VoiceOver: restore in progress"))
                }
            }

            if let package {
                Text(PaywallPricing.termsSentence(for: package))
                    .typeStyle(Typography.caption)
                    .foregroundStyle(Token.Text.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: Token.Layout.proseWidth)
                    .accessibilityLabel(PaywallPricing.termsSentence(for: package))
            }

            HStack(spacing: Token.Space.md) {
                legalLink(
                    String(localized: "Terms of Use", comment: "Legal link: EULA"),
                    destination: LegalLinks.termsOfUse
                )
                legalLink(
                    String(localized: "Privacy Policy", comment: "Legal link: privacy policy"),
                    destination: LegalLinks.privacyPolicy
                )
            }
            .frame(minHeight: Token.Size.minimumHitTarget)
        }
        .frame(maxWidth: .infinity)
    }

    /// Opens in Safari, out of process. Nothing in this app fetches these pages — see `LegalLinks`.
    private func legalLink(_ title: String, destination: URL) -> some View {
        Link(destination: destination) {
            Text(title)
                .typeStyle(Typography.label)
                .foregroundStyle(Token.Text.primary)
                .underline()
                .frame(minWidth: Token.Size.minimumHitTarget, minHeight: Token.Size.minimumHitTarget)
        }
        .accessibilityAddTraits(.isLink)
        .accessibilityHint(String(localized: "Opens in Safari.", comment: "VoiceOver hint on a legal link"))
    }
}
