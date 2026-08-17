import RevenueCat
import RevenueCatUI
import SwiftUI

/// The subscription screen. `AppCoordinator.presentPaywall()` leads here and nowhere else.
///
/// Two rendering paths, one behaviour:
///
/// - **Remote (primary).** When the offering RevenueCat served carries a paywall designed in the
///   dashboard, `RevenueCatUI.PaywallView` renders it. That is the capability worth having: the
///   layout, copy, imagery and package order can be changed — or A/B tested, see
///   ``PaywallExperiment`` — without shipping a build or waiting on App Review.
/// - **Native (fallback).** When the offering has no paywall, or no offering could be fetched at
///   all, ``NativePaywallView`` draws the screen from `Token`/`Typography`. A blank screen because a
///   dashboard was unreachable is a purchase the user wanted to make and could not.
///
/// Under **both** paths this view renders ``PaywallLegalFooter`` itself, so Restore Purchases, the
/// Terms of Use link, the Privacy Policy link and the auto-renewal sentence are compiled in rather
/// than dependent on a dashboard configuration that can change after the build ships.
///
/// The type is named `RedactPaywallView` rather than `PaywallView` deliberately: this file imports
/// `RevenueCatUI`, which exports its own `PaywallView`, and a same-named type here would force every
/// reference in the file to be module-qualified.
struct RedactPaywallView: View {

    @State private var store: PaywallStore
    private let usage: UsageTracker
    private let onUnlocked: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - context: why the paywall appeared. Drives the copy and the RevenueCat placement.
    ///   - entitlements: the app's one purchase state machine, injected by ``RouteDestination`` so
    ///     that a purchase made here is the same fact every locked feature elsewhere reads.
    ///   - usage: read for the "documents this month" facts on the quota wall.
    ///   - onUnlocked: called after `pro` becomes active, immediately before dismissing, so the
    ///     caller can resume the exact action the user was blocked from. The paywall never guesses
    ///     what that was.
    init(
        context: PaywallContext,
        entitlements: EntitlementStore,
        usage: UsageTracker = .shared,
        onUnlocked: @escaping () -> Void = {}
    ) {
        _store = State(initialValue: PaywallStore(context: context, entitlements: entitlements))
        self.usage = usage
        self.onUnlocked = onUnlocked
    }

    var body: some View {
        content
            .ambientBackground()
            .task { await store.load() }
            // The entitlement can also become active while this screen is open without a tap here —
            // a renewal, or a purchase made on another device signed into the same Apple Account.
            // `EntitlementStore` holds the app's one listener; this is how that reaches the screen.
            .onChange(of: store.isPro) { _, isPro in
                if isPro { store.markUnlocked() }
            }
            .onChange(of: store.justUnlocked) { _, unlocked in
                guard unlocked else { return }
                // Success is not a screen. The user was in the middle of something when they hit
                // the wall; the correct celebration is putting them straight back into it.
                onUnlocked()
                dismiss()
            }
            .alert(
                String(localized: "Purchase", comment: "Alert title for a purchase problem"),
                isPresented: alertBinding,
                presenting: store.alertMessage
            ) { _ in
                Button(String(localized: "OK", comment: "Alert dismiss button"), role: .cancel) {
                    store.alertMessage = nil
                }
            } message: { message in
                Text(message)
            }
            .alert(
                String(localized: "Nothing to restore", comment: "Alert title: restore found no purchase"),
                isPresented: $store.restoreFoundNothing
            ) {
                Button(String(localized: "OK", comment: "Alert dismiss button"), role: .cancel) {}
            } message: {
                Text(String(
                    localized: "There's no Redact Pro purchase on this Apple Account. If you bought Pro with a different Apple Account, sign in with that one and try again.",
                    comment: "Explains a restore that found no purchase"
                ))
            }
    }

    @ViewBuilder
    private var content: some View {
        if let offering = store.offering, offering.hasPaywall {
            remotePaywall(offering)
        } else {
            NativePaywallView(store: store, usage: usage, onDismiss: { dismiss() })
        }
    }

    // MARK: - Remote

    /// The dashboard-designed paywall, with our own compliance footer pinned beneath it.
    private func remotePaywall(_ offering: Offering) -> some View {
        VStack(spacing: 0) {
            PaywallView(offering: offering, displayCloseButton: true)
                // The remote paywall performs the purchase itself; we only need to re-read the
                // entitlement, because the entitlement — not the transaction — is what unlocks Pro.
                .onPurchaseCompleted { _ in
                    Task { await store.refreshEntitlement() }
                }
                .onRestoreCompleted { _ in
                    Task { await store.refreshEntitlement() }
                }
                // Deliberately empty: a user-initiated cancel is not an error and gets no alert.
                .onPurchaseCancelled { }
                .onRequestedDismissal { dismiss() }

            PaywallLegalFooter(
                package: footerPackage(for: offering),
                isRestoring: store.activity == .restoring,
                restore: { Task { await store.restore() } }
            )
            .padding(Token.Space.md)
            .background(Token.BG.section)
        }
    }

    /// Which plan the footer's auto-renewal sentence describes on the remote path.
    ///
    /// The remote paywall owns its own selection and does not report it, so the disclosure is
    /// written for the plan we recommend and preselect — annual — falling back through monthly to
    /// lifetime. Every plan's own terms are also spoken by its row on the native path, and the
    /// App Store sheet states them again at the point of purchase.
    private func footerPackage(for offering: Offering) -> Package? {
        offering.annual ?? offering.monthly ?? offering.lifetime
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { store.alertMessage != nil },
            set: { presented in if !presented { store.alertMessage = nil } }
        )
    }
}
