import Foundation
import Observation
import RevenueCat

// MARK: - Failure

/// A subscription operation that genuinely failed. **A cancelled purchase never becomes one of
/// these** — see ``PurchaseResult``.
public struct EntitlementFailure: Error, Sendable, Equatable {

    /// RevenueCat's code, when the error came from the SDK.
    public let code: ErrorCode?

    /// Message shown to the user. RevenueCat's `localizedDescription` is written for humans
    /// ("There was a problem with the App Store."), so it is used rather than reworded.
    public let message: String

    /// True when the operation failed because the device could not reach the store.
    ///
    /// The distinction is load-bearing: on a network failure the store keeps whatever Pro status it
    /// already had (see ``EntitlementStore/refresh()``), and the paywall can say "you're offline"
    /// instead of "purchase failed".
    public var isOffline: Bool {
        code == .networkError || code == .offlineConnectionError
    }

    public init(code: ErrorCode?, message: String) {
        self.code = code
        self.message = message
    }

    /// Builds a failure from anything the SDK throws.
    ///
    /// RevenueCat surfaces public errors as `NSError` in `ErrorCode.errorDomain`, so both the Swift
    /// enum and the bridged form are recognised. An unrecognised error still produces a real
    /// message rather than a shrug.
    public init(_ error: Error) {
        self.init(code: EntitlementFailure.errorCode(of: error),
                  message: (error as NSError).localizedDescription)
    }

    /// True when the user simply dismissed the payment sheet.
    public static func isUserCancellation(_ error: Error) -> Bool {
        errorCode(of: error) == .purchaseCancelledError
    }

    static func errorCode(of error: Error) -> ErrorCode? {
        if let code = error as? ErrorCode { return code }
        let nsError = error as NSError
        guard nsError.domain == ErrorCode.errorDomain else { return nil }
        return ErrorCode(rawValue: nsError.code)
    }
}

// MARK: - Purchase result

/// What came of a purchase attempt.
///
/// Three cases, not two, because "the user tapped Cancel" and "the payment failed" must not be
/// presented the same way. An error alert on Cancel is the single most common way a paywall annoys
/// both real users and the reviewer deciding whether this app ships.
public enum PurchaseResult: Sendable, Equatable {
    case purchased
    case cancelled
    case failed(EntitlementFailure)
}

/// What came of a restore attempt. `nothingToRestore` is a distinct, non-error outcome: someone who
/// never subscribed and taps Restore has done nothing wrong, and telling them "restore failed"
/// sends them to support for a non-problem.
public enum RestoreResult: Sendable, Equatable {
    case restoredPro
    case nothingToRestore
    case failed(EntitlementFailure)
}

// MARK: - Store

/// The single source of truth for "is this user Pro".
///
/// Two rules shape everything below.
///
/// **1. Never poll.** RevenueCat pushes a new `CustomerInfo` on renewal, expiry, billing failure,
/// and on purchases made from another device signed into the same Apple ID. ``observeUpdates()``
/// consumes that stream for the lifetime of the app, so a subscription that lapses mid-session
/// flips `isPro` without anyone asking.
///
/// **2. Never fail closed.** A network error must never revoke Pro. A paying user on a plane, on a
/// train, or behind a captive portal keeps everything they paid for; the SDK's cached
/// `CustomerInfo` is authoritative until the servers say otherwise. Locking a paying customer out
/// because a request timed out is worse than briefly honouring a subscription that has just
/// expired — one is a refund request and a one-star review, the other costs nothing.
@Observable
@MainActor
public final class EntitlementStore {

    // MARK: State

    /// Whether the `pro` entitlement is active. The only question the rest of the app asks.
    public private(set) var isPro = false

    /// The last `CustomerInfo` seen, from any source (cache, fetch, purchase, restore, stream).
    public private(set) var customerInfo: CustomerInfo?

    /// True while a refresh, restore or purchase is in flight. Drives spinners; never gates
    /// entitlement reads.
    public private(set) var isLoading = false

    /// The last real failure. Cleared at the start of every operation, and never set by a user
    /// cancellation.
    public private(set) var lastError: EntitlementFailure?

    /// The offering the paywall renders. `nil` until loaded, or when the dashboard has none.
    public private(set) var currentOffering: Offering?

    /// When the entitlement expires, if it is an expiring one. Surfaced so the paywall can say
    /// "renews on…" without reaching into `CustomerInfo` itself.
    public private(set) var proExpirationDate: Date?

    // MARK: Dependencies

    private let gateway: any EntitlementGateway
    private let entitlementIdentifier: String
    private var updatesTask: Task<Void, Never>?

    public init(
        gateway: any EntitlementGateway = RevenueCatGateway(),
        entitlementIdentifier: String = RevenueCatConfig.proEntitlementIdentifier
    ) {
        self.gateway = gateway
        self.entitlementIdentifier = entitlementIdentifier
    }

    // MARK: - Lifecycle

    /// Adopts the SDK's cached entitlement immediately, starts listening for updates, then refreshes.
    ///
    /// Order matters. The cache is read **first and synchronously with respect to the network**, so
    /// a returning Pro user is Pro before the first frame rather than a beat later — an app that
    /// shows a paywall for half a second on every cold launch reads as broken.
    ///
    /// Idempotent: calling it twice does not open a second stream.
    public func start() {
        guard updatesTask == nil else { return }

        // Both tasks inherit `@MainActor` from this method, so `apply` is a direct call and the
        // published properties are only ever written on the main actor.
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await info in self.gateway.customerInfoUpdates {
                self.apply(info)
            }
        }

        Task { [weak self] in
            guard let self else { return }
            if let cached = await self.gateway.cachedCustomerInfo() {
                self.apply(cached)
            }
            await self.refresh()
        }
    }

    /// Stops listening. Only the app teardown path needs this; exposed so tests do not leak tasks.
    public func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    // MARK: - Operations

    /// Re-reads entitlements, preferring fresh data and tolerating its absence.
    ///
    /// On failure the previously known status is kept and the error is recorded for the UI. It does
    /// **not** clear `isPro`; that only ever happens when the servers (or the cache) actually say
    /// the entitlement is inactive.
    public func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            apply(try await gateway.currentCustomerInfo())
        } catch {
            lastError = EntitlementFailure(error)

            // Fail *open*: if the SDK still has a cached answer, use it. If it does not, leave
            // whatever we already had in place rather than revoking access on a timeout.
            if let cached = await gateway.cachedCustomerInfo() {
                apply(cached)
            }
        }
    }

    /// Loads the offering the paywall shows. Kept separate from ``refresh()`` because a paywall
    /// that cannot list products is a different failure from one that cannot read entitlements, and
    /// only the first should stop the screen from appearing.
    public func loadOffering() async {
        do {
            currentOffering = try await gateway.currentOffering()
        } catch {
            lastError = EntitlementFailure(error)
        }
    }

    /// Restores previous purchases. Required on the paywall by App Review.
    @discardableResult
    public func restore() async -> RestoreResult {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let info = try await gateway.restorePurchases()
            apply(info)
            return isPro ? .restoredPro : .nothingToRestore
        } catch {
            let failure = EntitlementFailure(error)
            lastError = failure
            return .failed(failure)
        }
    }

    /// Buys `package`.
    ///
    /// A cancellation returns `.cancelled` and leaves `lastError` `nil`, so a caller that shows an
    /// alert whenever `lastError != nil` cannot accidentally scold someone for changing their mind.
    /// Both cancellation shapes are handled: the SDK reports it through `userCancelled` on
    /// StoreKit 2 and by throwing `purchaseCancelledError` on other paths.
    @discardableResult
    public func purchase(_ package: Package) async -> PurchaseResult {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let outcome = try await gateway.purchase(package)

            if let info = outcome.customerInfo {
                apply(info)
            }

            if outcome.userCancelled {
                return .cancelled
            }

            return .purchased
        } catch {
            if EntitlementFailure.isUserCancellation(error) {
                return .cancelled
            }

            let failure = EntitlementFailure(error)
            lastError = failure
            return .failed(failure)
        }
    }

    // MARK: - Applying

    /// The one place `isPro` is written.
    ///
    /// `entitlements.all[…]?.isActive` rather than `entitlements.active[…]`: `active` filters by
    /// environment, which in a sandbox or Test Store build would report a genuinely-purchased
    /// entitlement as inactive and lock the reviewer out of everything they were asked to check.
    private func apply(_ info: CustomerInfo) {
        customerInfo = info

        let entitlement = info.entitlements.all[entitlementIdentifier]
        isPro = entitlement?.isActive == true
        proExpirationDate = entitlement?.expirationDate
    }
}
