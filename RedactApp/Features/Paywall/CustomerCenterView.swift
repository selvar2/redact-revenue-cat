import RevenueCat
import RevenueCatUI
import SwiftUI

/// Self-service subscription management: change plan, cancel, request a refund, get help.
///
/// This wraps RevenueCat's **Customer Center**, which is remote-configured like the paywall — the
/// help paths, the cancellation survey and the promotional-offer flows are edited in the dashboard,
/// so support policy can change without an app update.
///
/// Why wrap it rather than route straight to Apple's manage-subscriptions sheet: Apple's sheet can
/// only cancel. The Customer Center can offer a win-back before the cancellation, hand the user a
/// refund request without a support email, and answer "why was I charged" in place — which is the
/// difference between a churned subscriber and a retained one, and between a refund and a one-star
/// review.
///
/// Named `ManageSubscriptionView` because this file imports `RevenueCatUI`, which exports its own
/// `CustomerCenterView`; a same-named type here would shadow it inside this very file.
struct ManageSubscriptionView: View {

    @Environment(\.dismiss) private var dismiss

    /// Called when a restore inside the Customer Center turns the entitlement on, so the surface
    /// that presented this (About, Settings) can refresh what it shows without polling.
    let onEntitlementChanged: () -> Void

    init(onEntitlementChanged: @escaping () -> Void = {}) {
        self.onEntitlementChanged = onEntitlementChanged
    }

    var body: some View {
        CustomerCenterView()
            .onCustomerCenterRestoreCompleted { _ in
                onEntitlementChanged()
            }
            .accessibilityLabel(String(
                localized: "Manage your subscription",
                comment: "VoiceOver label for the Customer Center screen"
            ))
    }
}

// MARK: - Presentation

extension View {

    /// Presents the Customer Center as a sheet.
    ///
    /// Exists so the surface that offers it — About, or a Settings row — needs one line and no
    /// RevenueCat import of its own:
    ///
    /// ```swift
    /// SecondaryButton("Manage subscription") { showManage = true }
    ///     .manageSubscriptionSheet(isPresented: $showManage)
    /// ```
    ///
    /// Show it to **everyone**, not only to current subscribers: a user whose subscription has
    /// lapsed, or who bought on another Apple Account, is exactly the person who needs it, and a row
    /// that appears and disappears based on entitlement state is one users cannot find twice.
    func manageSubscriptionSheet(
        isPresented: Binding<Bool>,
        onEntitlementChanged: @escaping () -> Void = {}
    ) -> some View {
        sheet(isPresented: isPresented) {
            ManageSubscriptionView(onEntitlementChanged: onEntitlementChanged)
        }
    }
}
