import RevenueCat
import SwiftUI

/// The paywall the app draws itself, from `Token`/`Typography`, when there is no remote paywall to
/// render — the offering has no paywall configured, or the offering could not be fetched at all.
///
/// This is not a placeholder. A paywall that fails to appear because a dashboard was unreachable is
/// a purchase the user wanted to make and could not, so this path has to be complete: real prices
/// from `StoreProduct`, the required disclosure, Restore Purchases, both legal links, and a way back
/// to the free tier that still works.
struct NativePaywallView: View {

    @Bindable var store: PaywallStore
    let usage: UsageTracker
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Token.Space.lg) {
                header

                switch store.loadState {
                case .loading:
                    loading
                case .ready:
                    plans
                    callToAction
                case .unavailable(let message):
                    unavailable(message)
                }

                PaywallLegalFooter(
                    package: store.selectedPackage,
                    isRestoring: store.activity == .restoring,
                    restore: { Task { await store.restore() } }
                )

                freeTierEscape

                #if DEBUG
                if let offering = store.offering {
                    Text(PaywallExperiment.debugAttribution(for: offering))
                        .typeStyle(Typography.caption)
                        .foregroundStyle(Token.Text.faint)
                        .accessibilityHidden(true)
                }
                #endif
            }
            .padding(Token.Space.md)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Token.Space.sm) {
            IconWell(store.context.symbolName, size: Token.Size.mark, tint: .gradient)

            Pill(store.context.eyebrow, style: .accent)

            Text(store.context.headline)
                .typeStyle(Typography.displayLarge)
                .foregroundStyle(Token.Text.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(store.context.message)
                .typeStyle(Typography.body)
                .foregroundStyle(Token.Text.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Token.Layout.proseWidth)
                .fixedSize(horizontal: false, vertical: true)

            if store.context == .monthlyLimit {
                quotaFacts
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The two numbers behind the wall the user just hit, read from `UsageTracker` so the screen
    /// cannot drift out of step with the rule it is explaining.
    private var quotaFacts: some View {
        VStack(alignment: .leading, spacing: Token.Space.xs) {
            fact(
                String(localized: "Documents this month", comment: "Quota fact label"),
                value: String(
                    format: String(localized: "%1$d of %2$d", comment: "Quota fact value, e.g. '3 of 3'"),
                    usage.documentsThisMonth,
                    UsageTracker.freeMonthlyAllowance
                )
            )
            fact(
                String(localized: "Your free allowance returns", comment: "Quota fact label: reset date"),
                value: usage.nextResetDate.formatted(date: .abbreviated, time: .omitted)
            )
        }
        .frame(maxWidth: Token.Layout.proseWidth)
        .glassCard()
    }

    private func fact(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .typeStyle(Typography.callout)
                .foregroundStyle(Token.Text.muted)
            Spacer(minLength: Token.Space.sm)
            Text(value)
                .typeStyle(Typography.bodyEmphasis)
                .foregroundStyle(Token.Text.primary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    // MARK: - States

    private var loading: some View {
        VStack(spacing: Token.Space.sm) {
            ProgressView()
            Text(String(localized: "Loading plans and prices for your region…", comment: "Paywall loading state"))
                .typeStyle(Typography.callout)
                .foregroundStyle(Token.Text.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Token.Space.lg)
        .accessibilityElement(children: .combine)
    }

    private func unavailable(_ message: String) -> some View {
        VStack(spacing: Token.Space.sm) {
            Text(message)
                .typeStyle(Typography.body)
                .foregroundStyle(Token.Text.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Token.Layout.proseWidth)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(
                String(localized: "Try again", comment: "Button: retry loading the plans"),
                systemImage: "arrow.clockwise"
            ) {
                Task { await store.load() }
            }
        }
        .frame(maxWidth: Token.Layout.proseWidth)
        .glassCard()
    }

    private var plans: some View {
        VStack(spacing: Token.Space.sm) {
            ForEach(store.displayPackages, id: \.identifier) { package in
                PaywallPlanRow(
                    package: package,
                    isSelected: package.identifier == store.selectedPackage?.identifier,
                    savingPercent: package.packageType == .annual ? store.annualSavingPercent : nil,
                    isBusy: store.isBusy,
                    action: { store.selectedPackageIdentifier = package.identifier }
                )
            }
        }
        .frame(maxWidth: Token.Layout.proseWidth)
    }

    private var callToAction: some View {
        VStack(spacing: Token.Space.xs) {
            PrimaryButton(
                buttonTitle,
                systemImage: "checkmark.shield",
                isLoading: isPurchasing
            ) {
                guard let package = store.selectedPackage else { return }
                Task { await store.purchase(package) }
            }
            .disabled(store.selectedPackage == nil || store.isBusy)

            Text(String(localized: "Everything stays on this device. Buying Pro sends no document anywhere.", comment: "Reassurance under the purchase button"))
                .typeStyle(Typography.caption)
                .foregroundStyle(Token.Text.faint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: Token.Layout.proseWidth)
    }

    /// Names the plan and its price on the button itself, so the thing the tap costs is legible
    /// without scrolling back up to the selected row.
    private var buttonTitle: String {
        guard let package = store.selectedPackage else {
            return String(localized: "Get Redact Pro", comment: "Purchase button, no plan loaded")
        }
        return String(
            format: String(localized: "Continue — %@", comment: "Purchase button with the selected plan's price"),
            PaywallPricing.priceLine(for: package)
        )
    }

    private var isPurchasing: Bool {
        if case .purchasing = store.activity { return true }
        return false
    }

    // MARK: - The way back

    /// The free tier remains usable, and the screen says so.
    ///
    /// A paywall the user cannot leave is both a rejection (Guideline 3.1.2) and a bad product: the
    /// documents they have already redacted are theirs, and the allowance returns next month.
    private var freeTierEscape: some View {
        VStack(spacing: Token.Space.xs) {
            SecondaryButton(
                String(localized: "Keep using Redact free", comment: "Button: dismiss the paywall and stay on the free tier"),
                prominence: .plain,
                action: onDismiss
            )

            Text(String(localized: "Your library stays open on the free plan — you can still view, share and delete everything you've already redacted.", comment: "Reassurance that the free tier keeps working"))
                .typeStyle(Typography.caption)
                .foregroundStyle(Token.Text.faint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Token.Layout.proseWidth)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
