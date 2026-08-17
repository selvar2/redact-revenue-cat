import Foundation
import Observation
import RevenueCat

/// The paywall's *screen* state: which offering to render, which plan is selected, what is in
/// flight, and what to say when something goes wrong.
///
/// It deliberately owns **no** purchase state. Buying, restoring and "is this user Pro" all belong
/// to the injected ``EntitlementStore``, which is the same instance the rest of the app reads
/// through `ProAccess`. Two stores each calling `Purchases.purchase` and each keeping their own
/// `isPro` is how a paying user ends up looking un-paid to half the app
/// (`docs/memory/gotchas/two-purchase-state-machines.md`); there is now one state machine, and
/// every rule about purchases — a cancel is not an error, the entitlement rather than the
/// transaction is the truth, a network failure never revokes Pro — is stated once, over there.
///
/// `@MainActor` because it feeds a view directly and every RevenueCat completion is delivered on the
/// main actor anyway. `Offering`, `Package` and `CustomerInfo` are all `Sendable`, so nothing has to
/// be copied out of them to cross a boundary.
@MainActor
@Observable
final class PaywallStore {

    /// What the screen should be showing.
    enum LoadState {
        case loading
        /// The server answered. `offering` is whichever arm ``PaywallExperiment`` resolved.
        case ready(Offering)
        /// No offering could be fetched. Carries a sentence the user can act on — never an SDK
        /// error dump, and never a dead end: the screen still shows Restore Purchases and Retry.
        case unavailable(String)
    }

    /// A purchase or restore in flight. Drives spinners and disables the plan rows.
    enum Activity: Equatable {
        case idle
        case purchasing(packageIdentifier: String)
        case restoring
    }

    private(set) var loadState: LoadState = .loading
    private(set) var activity: Activity = .idle

    /// True once `pro` is active for this user. Read straight from the app-wide entitlement store,
    /// so this screen and every locked feature elsewhere can never disagree.
    var isPro: Bool { entitlements.isPro }

    /// A message worth interrupting the user for. A cancelled purchase never sets this.
    var alertMessage: String?

    /// Set when a restore genuinely found nothing, so the screen can say so plainly instead of
    /// showing an error for a perfectly normal outcome.
    var restoreFoundNothing: Bool = false

    /// The package selected in the native fallback. Annual is preselected once the offering loads.
    var selectedPackageIdentifier: String?

    let context: PaywallContext

    /// The one purchase state machine in the app.
    private let entitlements: EntitlementStore

    /// Flips to `true` at the moment `pro` becomes active — by purchase, by restore, or by a change
    /// arriving on `customerInfoStream` while the screen is open.
    ///
    /// The view watches this and dismisses, which puts the user back exactly where they were when
    /// they hit the wall. It is a signal rather than a callback because the same unlock can arrive
    /// from three different places, and one observable fact is easier to reason about than three
    /// call sites that must all remember to fire it.
    private(set) var justUnlocked: Bool = false

    init(context: PaywallContext, entitlements: EntitlementStore) {
        self.context = context
        self.entitlements = entitlements
    }

    // MARK: - Derived

    var offering: Offering? {
        if case .ready(let offering) = loadState { return offering }
        return nil
    }

    /// The three packages we sell, in display order, filtered to what the offering actually contains.
    ///
    /// Built from `Offering.monthly/annual/lifetime` rather than from `availablePackages` so the
    /// order is ours and a fourth package added in the dashboard cannot rearrange the screen. A
    /// package the dashboard has not configured is simply absent — never an empty row (rule 10).
    var displayPackages: [Package] {
        guard let offering else { return [] }
        return [offering.annual, offering.monthly, offering.lifetime].compactMap { $0 }
    }

    var selectedPackage: Package? {
        displayPackages.first { $0.identifier == selectedPackageIdentifier } ?? displayPackages.first
    }

    /// Percentage the annual plan saves against twelve months of the monthly plan, or `nil` when
    /// there is nothing truthful to claim.
    var annualSavingPercent: Int? {
        PaywallPricing.annualSavingPercent(annual: offering?.annual, monthly: offering?.monthly)
    }

    var isBusy: Bool { activity != .idle }

    // MARK: - Loading

    /// Fetches the offering and the current entitlement state.
    ///
    /// Idempotent enough to be called from `.task`: a second call simply refetches, which is the
    /// right behaviour after a network blip and a Retry tap.
    func load() async {
        guard Purchases.isConfigured else {
            loadState = .unavailable(Self.notConfiguredMessage)
            return
        }

        loadState = .loading
        await refreshEntitlement()

        do {
            let offerings = try await Purchases.shared.offerings()
            guard let offering = PaywallExperiment.offering(from: offerings, context: context) else {
                loadState = .unavailable(Self.noOfferingMessage)
                return
            }
            loadState = .ready(offering)
            // Annual is preselected: it is the plan we recommend and the one the saving badge is
            // computed against. Selection is only ever a default — never a purchase.
            selectedPackageIdentifier = (offering.annual ?? offering.monthly ?? offering.lifetime)?.identifier
        } catch {
            loadState = .unavailable(Self.offlineMessage)
        }
    }

    /// Re-reads the entitlement. `EntitlementStore.refresh()` keeps the previous answer on a
    /// failure, so a transient error here can never lock a paying user out mid-purchase.
    ///
    /// Nothing subscribes to `customerInfoStream` from this screen: ``EntitlementStore`` holds the
    /// app's one subscription for the lifetime of the process, and because it is `@Observable` a
    /// renewal, expiry or cross-device purchase updates ``isPro`` here without a second listener.
    func refreshEntitlement() async {
        guard Purchases.isConfigured else { return }
        await entitlements.refresh()
    }

    /// Records that `pro` became active while this screen was open, whatever made it happen — this
    /// user's purchase, their restore, or a change pushed to ``EntitlementStore`` from another
    /// device. The view watches ``justUnlocked`` and dismisses.
    ///
    /// Someone who already held Pro when the screen opened is *not* unlocked by it: the view calls
    /// this from `onChange`, which only fires on a transition.
    func markUnlocked() {
        justUnlocked = true
    }

    // MARK: - Purchase

    /// Buys `package`.
    ///
    /// A user-initiated cancel returns silently to `.idle`. Showing "Purchase failed" for someone
    /// who tapped Cancel is the single most common way a paywall reads as hostile, and Apple's own
    /// sheet has already told them nothing happened.
    func purchase(_ package: Package) async {
        guard Purchases.isConfigured else {
            alertMessage = Self.notConfiguredMessage
            return
        }
        guard !isBusy else { return }

        activity = .purchasing(packageIdentifier: package.identifier)
        defer { activity = .idle }

        switch await entitlements.purchase(package) {
        case .cancelled:
            return
        case .failed(let failure):
            alertMessage = failure.message.isEmpty ? Self.genericFailureMessage : failure.message
        case .purchased:
            if isPro {
                justUnlocked = true
            } else {
                // StoreKit succeeded but the entitlement is not active — a deferred/pending purchase
                // (Ask to Buy) or a dashboard product not attached to `pro`. Saying "you're all set"
                // here would be a lie the user discovers at the next locked feature.
                alertMessage = Self.pendingMessage
            }
        }
    }

    // MARK: - Restore

    /// Restores previous purchases.
    ///
    /// Required on the paywall by App Review, and genuinely needed: a reinstall, a new device, or a
    /// family-shared purchase all arrive here. A restore that finds nothing is a normal outcome and
    /// is reported as a fact, not as an error.
    func restore() async {
        guard Purchases.isConfigured else {
            alertMessage = Self.notConfiguredMessage
            return
        }
        guard !isBusy else { return }

        activity = .restoring
        defer { activity = .idle }

        switch await entitlements.restore() {
        case .restoredPro:
            justUnlocked = true
        case .nothingToRestore:
            restoreFoundNothing = true
        case .failed(let failure):
            alertMessage = failure.message.isEmpty ? Self.genericFailureMessage : failure.message
        }
    }

    // MARK: - Messages

    private static let notConfiguredMessage = String(
        localized: "Purchases aren't available in this build. Your documents and everything you've already redacted are unaffected.",
        comment: "Shown when the RevenueCat SDK was not configured"
    )

    private static let noOfferingMessage = String(
        localized: "We couldn't load the plans just now. You can try again, or restore a purchase you've already made.",
        comment: "Shown when no offering came back from the server"
    )

    private static let offlineMessage = String(
        localized: "We couldn't reach the App Store to load prices. Redact itself works offline — only buying needs a connection.",
        comment: "Shown when fetching offerings failed"
    )

    private static let pendingMessage = String(
        localized: "Your purchase is being processed. Pro unlocks as soon as it's approved — nothing else is needed from you.",
        comment: "Shown when a purchase succeeded but the entitlement is not yet active"
    )

    private static let genericFailureMessage = String(
        localized: "That purchase didn't go through. You haven't been charged. You can try again, or restore a previous purchase.",
        comment: "Fallback purchase error message"
    )
}
