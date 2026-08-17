import XCTest
import RevenueCat
@testable import RedactApp

/// The entitlement state machine, driven entirely through a mocked gateway.
///
/// **Nothing here touches the network** (CLAUDE.md rule 1): `Purchases` is never configured, and
/// the `CustomerInfo` fixtures are built with RevenueCat's public test initialisers.
///
/// The cases that matter are the ones that cost money or trust if they are wrong:
/// a cancel is not an error, an expiry revokes Pro, and a network failure does **not**.
@MainActor
final class EntitlementStoreTests: XCTestCase {

    // MARK: - Fixtures

    private static let entitlementID = RevenueCatConfig.proEntitlementIdentifier

    private func customerInfo(pro: Bool, expiration: Date? = nil) -> CustomerInfo {
        let entitlements: [String: EntitlementInfo]
        if pro {
            entitlements = [
                Self.entitlementID: EntitlementInfo(
                    identifier: Self.entitlementID,
                    isActive: true,
                    willRenew: true,
                    periodType: .normal,
                    latestPurchaseDate: Date(timeIntervalSince1970: 1_000),
                    originalPurchaseDate: Date(timeIntervalSince1970: 1_000),
                    expirationDate: expiration,
                    store: .appStore,
                    productIdentifier: RevenueCatConfig.ProductIdentifier.monthly,
                    isSandbox: true,
                    ownershipType: .purchased
                )
            ]
        } else {
            // An *expired* entitlement, not a missing one: this is the shape RevenueCat actually
            // sends after a lapse, and the store must read `isActive` rather than mere presence.
            entitlements = [
                Self.entitlementID: EntitlementInfo(
                    identifier: Self.entitlementID,
                    isActive: false,
                    willRenew: false,
                    periodType: .normal,
                    latestPurchaseDate: Date(timeIntervalSince1970: 1_000),
                    originalPurchaseDate: Date(timeIntervalSince1970: 1_000),
                    expirationDate: Date(timeIntervalSince1970: 2_000),
                    store: .appStore,
                    productIdentifier: RevenueCatConfig.ProductIdentifier.monthly,
                    isSandbox: true,
                    ownershipType: .purchased
                )
            ]
        }

        return CustomerInfo(
            entitlements: EntitlementInfos(entitlements: entitlements),
            requestDate: Date(timeIntervalSince1970: 3_000),
            firstSeen: Date(timeIntervalSince1970: 500),
            originalAppUserId: "test-user"
        )
    }

    private func package() -> Package {
        let product = TestStoreProduct(
            localizedTitle: "Redact Pro",
            price: 3.99,
            currencyCode: "USD",
            localizedPriceString: "$3.99",
            productIdentifier: RevenueCatConfig.ProductIdentifier.monthly,
            productType: .autoRenewableSubscription,
            localizedDescription: "Unlimited documents",
            locale: Locale(identifier: "en_US")
        )

        return Package(
            identifier: RevenueCatConfig.PackageIdentifier.monthly,
            packageType: .monthly,
            storeProduct: product.toStoreProduct(),
            presentedOfferingContext: PresentedOfferingContext(
                offeringIdentifier: RevenueCatConfig.defaultOfferingIdentifier
            ),
            webCheckoutUrl: nil
        )
    }

    // MARK: - Purchase

    func testPurchaseTurnsANonProUserIntoAProUser() async {
        let gateway = MockGateway()
        await gateway.setCached(customerInfo(pro: false))
        await gateway.setPurchaseOutcome(
            .success(PurchaseOutcome(customerInfo: customerInfo(pro: true), userCancelled: false))
        )

        let store = EntitlementStore(gateway: gateway)
        await store.refresh()
        XCTAssertFalse(store.isPro)

        let result = await store.purchase(package())

        XCTAssertEqual(result, .purchased)
        XCTAssertTrue(store.isPro)
        XCTAssertNil(store.lastError)
    }

    /// Reviewers tap Cancel on every paywall. An error alert here is a bad experience and reads as
    /// a broken purchase flow.
    func testUserCancellationIsNotAnError() async {
        let gateway = MockGateway()
        await gateway.setPurchaseOutcome(
            .success(PurchaseOutcome(customerInfo: nil, userCancelled: true))
        )

        let store = EntitlementStore(gateway: gateway)
        let result = await store.purchase(package())

        XCTAssertEqual(result, .cancelled)
        XCTAssertNil(store.lastError, "Cancelling must never populate an error the UI would show")
        XCTAssertFalse(store.isPro)
    }

    /// The other shape of the same event: some StoreKit paths report a cancel by throwing.
    func testThrownCancellationIsAlsoNotAnError() async {
        let gateway = MockGateway()
        await gateway.setPurchaseOutcome(.failure(ErrorCode.purchaseCancelledError))

        let store = EntitlementStore(gateway: gateway)
        let result = await store.purchase(package())

        XCTAssertEqual(result, .cancelled)
        XCTAssertNil(store.lastError)
    }

    func testARealPurchaseFailureIsReported() async {
        let gateway = MockGateway()
        await gateway.setPurchaseOutcome(.failure(ErrorCode.storeProblemError))

        let store = EntitlementStore(gateway: gateway)
        let result = await store.purchase(package())

        guard case .failed(let failure) = result else {
            return XCTFail("Expected a failure, got \(result)")
        }
        XCTAssertEqual(failure.code, .storeProblemError)
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.isPro)
    }

    // MARK: - Restore

    func testRestoreGrantsProWhenThePurchaseExists() async {
        let gateway = MockGateway()
        await gateway.setRestoreResult(.success(customerInfo(pro: true)))

        let store = EntitlementStore(gateway: gateway)
        let result = await store.restore()

        XCTAssertEqual(result, .restoredPro)
        XCTAssertTrue(store.isPro)
    }

    /// Someone who never subscribed and taps Restore has done nothing wrong. Reporting that as a
    /// failure sends them to support for a non-problem.
    func testRestoreWithNothingToRestoreIsNotAFailure() async {
        let gateway = MockGateway()
        await gateway.setRestoreResult(.success(customerInfo(pro: false)))

        let store = EntitlementStore(gateway: gateway)
        let result = await store.restore()

        XCTAssertEqual(result, .nothingToRestore)
        XCTAssertFalse(store.isPro)
        XCTAssertNil(store.lastError)
    }

    // MARK: - Expiry

    func testExpiryRevokesPro() async {
        let gateway = MockGateway()
        await gateway.setCurrent(.success(customerInfo(pro: true)))

        let store = EntitlementStore(gateway: gateway)
        await store.refresh()
        XCTAssertTrue(store.isPro)

        // The renewal did not happen; RevenueCat now reports the entitlement inactive.
        await gateway.setCurrent(.success(customerInfo(pro: false)))
        await store.refresh()

        XCTAssertFalse(store.isPro)
    }

    /// The push path: no polling anywhere in the store, so an expiry that arrives on the stream
    /// must flip the flag on its own.
    func testAnExpiryArrivingOnTheStreamFlipsIsPro() async {
        let gateway = MockGateway()
        await gateway.setCached(customerInfo(pro: true))
        await gateway.setCurrent(.success(customerInfo(pro: true)))

        let store = EntitlementStore(gateway: gateway)
        store.start()
        await eventually("the cached Pro entitlement is adopted") { store.isPro }

        gateway.emit(customerInfo(pro: false))
        await eventually("the streamed expiry revokes Pro") { !store.isPro }

        store.stop()
    }

    // MARK: - Offline

    /// The rule that matters most: a paying user on a plane stays Pro. Never fail closed.
    func testANetworkFailurePreservesCachedPro() async {
        let gateway = MockGateway()
        await gateway.setCached(customerInfo(pro: true))
        await gateway.setCurrent(.failure(ErrorCode.networkError))

        let store = EntitlementStore(gateway: gateway)
        await store.refresh()

        XCTAssertTrue(store.isPro, "A network failure must never revoke a paid entitlement")
        XCTAssertEqual(store.lastError?.code, .networkError)
        XCTAssertEqual(store.lastError?.isOffline, true)
    }

    /// Same rule with an empty SDK cache: the store keeps what it already knew rather than
    /// resetting to not-Pro.
    func testANetworkFailureWithNoCacheKeepsTheStatusAlreadyKnown() async {
        let gateway = MockGateway()
        await gateway.setCurrent(.success(customerInfo(pro: true)))

        let store = EntitlementStore(gateway: gateway)
        await store.refresh()
        XCTAssertTrue(store.isPro)

        await gateway.setCurrent(.failure(ErrorCode.offlineConnectionError))
        await gateway.setCached(nil)
        await store.refresh()

        XCTAssertTrue(store.isPro, "A timeout is not evidence that a subscription ended")
    }

    // MARK: - The free-tier bridge

    func testProBypassesTheFreeMonthlyLimit() async {
        let defaults = UserDefaults(suiteName: "EntitlementStoreTests.\(UUID().uuidString)")!
        let usage = UsageTracker(defaults: defaults)
        for _ in 0 ..< UsageTracker.freeMonthlyAllowance { usage.recordDocumentProcessed() }
        XCTAssertFalse(usage.canProcessDocument(), "Precondition: the free tier is spent")

        let gateway = MockGateway()
        await gateway.setCurrent(.success(customerInfo(pro: false)))
        let store = EntitlementStore(gateway: gateway)
        await store.refresh()

        let allowance = store.allowance(usage: usage)
        XCTAssertFalse(allowance.canProcessDocument())
        XCTAssertEqual(allowance.remainingFreeDocuments, 0)

        await gateway.setCurrent(.success(customerInfo(pro: true)))
        await store.refresh()

        XCTAssertTrue(allowance.canProcessDocument(), "Pro must bypass the 3-a-month limit")
        XCTAssertNil(allowance.remainingFreeDocuments, "A limit that does not apply must not be shown")
    }

    // MARK: - Helpers

    /// Polls a main-actor condition with a deadline. Used only for the two stream tests, where the
    /// value arrives on a task the test did not create and there is nothing to `await` directly.
    private func eventually(
        _ description: String,
        timeout: TimeInterval = 2,
        condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for: \(description)", file: file, line: line)
    }
}

// MARK: - Mock

/// A gateway with no RevenueCat behind it.
///
/// An `actor` rather than a class because ``EntitlementGateway`` is `Sendable` and its methods are
/// `async`; the stream and its continuation are `nonisolated let` because both are `Sendable` and
/// the store reads the stream from the main actor.
private actor MockGateway: EntitlementGateway {

    nonisolated let customerInfoUpdates: AsyncStream<CustomerInfo>
    private nonisolated let continuation: AsyncStream<CustomerInfo>.Continuation

    private var cached: CustomerInfo?
    private var current: Result<CustomerInfo, Error> = .failure(ErrorCode.unknownError)
    private var restoreResult: Result<CustomerInfo, Error> = .failure(ErrorCode.unknownError)
    private var purchaseOutcome: Result<PurchaseOutcome, Error> = .failure(ErrorCode.unknownError)

    init() {
        var escapee: AsyncStream<CustomerInfo>.Continuation!
        self.customerInfoUpdates = AsyncStream { escapee = $0 }
        self.continuation = escapee
    }

    func setCached(_ info: CustomerInfo?) { cached = info }
    func setCurrent(_ result: Result<CustomerInfo, Error>) { current = result }
    func setRestoreResult(_ result: Result<CustomerInfo, Error>) { restoreResult = result }
    func setPurchaseOutcome(_ result: Result<PurchaseOutcome, Error>) { purchaseOutcome = result }

    /// Simulates RevenueCat pushing a new `CustomerInfo` — a renewal, an expiry, or a purchase made
    /// on another device.
    nonisolated func emit(_ info: CustomerInfo) {
        continuation.yield(info)
    }

    func cachedCustomerInfo() async -> CustomerInfo? { cached }
    func currentCustomerInfo() async throws -> CustomerInfo { try current.get() }
    func restorePurchases() async throws -> CustomerInfo { try restoreResult.get() }
    func purchase(_ package: Package) async throws -> PurchaseOutcome { try purchaseOutcome.get() }
    func currentOffering() async throws -> Offering? { nil }
}
