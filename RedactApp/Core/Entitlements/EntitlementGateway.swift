import Foundation
import RevenueCat

/// The RevenueCat surface ``EntitlementStore`` uses, expressed as a protocol.
///
/// The store's job is a state machine — cached versus fresh, cancelled versus failed, expired
/// versus offline — and that machine is exactly the part that must be testable without a network,
/// a StoreKit configuration, or a configured SDK (CLAUDE.md rule 1: tests make no network calls
/// either). Everything that actually talks to RevenueCat lives in ``RevenueCatGateway`` and is a
/// straight pass-through with no branching, so there is nothing in it a test could catch.
///
/// `Sendable` and `async` throughout: the store is `@MainActor`, the SDK is not, and every value
/// crossing that boundary (`CustomerInfo`, `Package`, `Offering`) is `Sendable` already.
public protocol EntitlementGateway: Sendable {

    /// Pushes a new `CustomerInfo` whenever RevenueCat learns of one — a renewal, an expiry, a
    /// purchase made on another device, a restore. This is why the store never polls.
    var customerInfoUpdates: AsyncStream<CustomerInfo> { get }

    /// The SDK's cached `CustomerInfo`, without touching the network. `nil` when there has never
    /// been one on this device.
    func cachedCustomerInfo() async -> CustomerInfo?

    /// Current `CustomerInfo`, fetching only if the cache is stale. Throws when the fetch fails and
    /// there is nothing cached to fall back on.
    func currentCustomerInfo() async throws -> CustomerInfo

    /// Restores purchases for the current store account.
    func restorePurchases() async throws -> CustomerInfo

    /// Buys `package`. A user tapping Cancel is a normal outcome, not an error — see
    /// ``PurchaseOutcome``.
    func purchase(_ package: Package) async throws -> PurchaseOutcome

    /// The offering the paywall should display, or `nil` when the dashboard has none configured.
    func currentOffering() async throws -> Offering?
}

/// The result of a purchase attempt that did not throw.
///
/// `userCancelled` is a first-class outcome rather than an error because the SDK reports it as one:
/// on StoreKit 2 a tap on Cancel comes back through this tuple, not through `throw`. Collapsing it
/// into a failure is how apps end up showing "Purchase failed" to someone who simply changed their
/// mind — and App Review taps Cancel on every paywall they see.
public struct PurchaseOutcome: Sendable {
    public let customerInfo: CustomerInfo?
    public let userCancelled: Bool

    public init(customerInfo: CustomerInfo?, userCancelled: Bool) {
        self.customerInfo = customerInfo
        self.userCancelled = userCancelled
    }
}

/// The real gateway. Every method is a one-line pass-through to `Purchases.shared` on purpose:
/// logic here would be logic no test can reach.
public struct RevenueCatGateway: EntitlementGateway {

    public init() {}

    public var customerInfoUpdates: AsyncStream<CustomerInfo> {
        Purchases.shared.customerInfoStream
    }

    public func cachedCustomerInfo() async -> CustomerInfo? {
        // A cache miss is an expected state on first launch, not a failure worth surfacing.
        try? await Purchases.shared.customerInfo(fetchPolicy: .fromCacheOnly)
    }

    public func currentCustomerInfo() async throws -> CustomerInfo {
        try await Purchases.shared.customerInfo(fetchPolicy: .cachedOrFetched)
    }

    public func restorePurchases() async throws -> CustomerInfo {
        try await Purchases.shared.restorePurchases()
    }

    public func purchase(_ package: Package) async throws -> PurchaseOutcome {
        let result = try await Purchases.shared.purchase(package: package)
        return PurchaseOutcome(customerInfo: result.customerInfo, userCancelled: result.userCancelled)
    }

    public func currentOffering() async throws -> Offering? {
        let offerings = try await Purchases.shared.offerings()
        // Named lookup first so the app and the dashboard agree, `current` second so a renamed or
        // experiment-swapped offering still gives the paywall something real to show.
        return offerings.all[RevenueCatConfig.defaultOfferingIdentifier] ?? offerings.current
    }
}
