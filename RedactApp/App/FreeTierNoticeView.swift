import SwiftUI

/// What `AppCoordinator.presentPaywall()` shows until purchases exist.
///
/// The coordinator has a paywall seam from Phase 2 so that quota checks in Scan and Export have
/// somewhere to send the user from day one. Until Phase 3 wires RevenueCat, that destination cannot
/// be a subscription screen — but it must not be an empty sheet either, and it must not promise a
/// product the build does not contain — a teaser for an unshipped feature is CLAUDE.md rule 10 and
/// App Review guideline 4.2 in one line.
///
/// So it states the limit as a fact, says exactly when it resets, and gives the user the only two
/// real ways forward that exist today: go back, or free up a slot. Every number below is read from
/// `UsageTracker`, so the screen cannot drift out of step with the rule it is explaining.
///
/// **Phase 3 replaces this**: `feature-paywall` swaps the `.paywall` case in ``RouteDestination``
/// for the real purchase screen. That is a one-line change, and this file is then deleted.
struct FreeTierNoticeView: View {

    @Environment(\.dismiss) private var dismiss

    private let usage: UsageTracker

    init(usage: UsageTracker = .shared) {
        self.usage = usage
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Token.Space.lg) {
                IconWell("calendar.badge.clock", size: Token.Size.mark, tint: .gradient)

                VStack(spacing: Token.Space.sm) {
                    Text(headline)
                        .typeStyle(Typography.displayLarge)
                        .foregroundStyle(Token.Text.primary)
                        .multilineTextAlignment(.center)

                    Text(explanation)
                        .typeStyle(Typography.body)
                        .foregroundStyle(Token.Text.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: Token.Layout.proseWidth)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: Token.Space.sm) {
                    fact("Documents redacted this month", value: "\(usage.documentsThisMonth) of \(UsageTracker.freeMonthlyAllowance)")
                    fact("Your allowance resets", value: resetDescription)
                }
                .frame(maxWidth: Token.Layout.proseWidth)
                .glassCard()

                Text("Documents you have already redacted stay in your library, and you can still open, share and delete them.")
                    .typeStyle(Typography.callout)
                    .foregroundStyle(Token.Text.faint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Token.Layout.proseWidth)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton("Back to my documents") { dismiss() }
                    .frame(maxWidth: Token.Layout.proseWidth)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Token.Space.lg)
            .padding(.vertical, Token.Space.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .ambientBackground()
        .navigationTitle("Monthly limit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .accessibilityLabel("Close")
            }
        }
    }

    // MARK: - Copy

    private var headline: String {
        usage.canProcessDocument()
            ? "You have \(usage.remainingFreeDocuments) documents left this month"
            : "You've used this month's free documents"
    }

    private var explanation: String {
        """
        Redact does all of its work on your device, and the free version covers \
        \(UsageTracker.freeMonthlyAllowance) documents a month.
        """
    }

    private var resetDescription: String {
        usage.nextResetDate.formatted(date: .abbreviated, time: .omitted)
    }

    private func fact(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Token.Space.sm) {
            Text(label)
                .typeStyle(Typography.callout)
                .foregroundStyle(Token.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .typeStyle(Typography.bodyEmphasis)
                .foregroundStyle(Token.Text.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

#Preview("Free tier notice") {
    NavigationStack { FreeTierNoticeView() }
        .preferredColorScheme(.dark)
}
