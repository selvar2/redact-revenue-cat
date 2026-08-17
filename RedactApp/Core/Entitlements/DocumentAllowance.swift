import Foundation

/// The single question a feature asks before doing paid work: *may this user process a document?*
///
/// Two facts answer it — the RevenueCat entitlement and the free-tier counter — and every feature
/// that asked them separately would eventually get the combination wrong in the direction that
/// blocks a paying customer. So they are combined **here**, once:
///
/// ```swift
/// guard allowance.canProcessDocument() else {
///     coordinator.presentPaywall()
///     return
/// }
/// ```
///
/// `UsageTracker` is untouched by design. It lives in `Core/Persistence` (another agent's lane) and
/// deliberately knows nothing about purchases — it is a counter. Teaching it about entitlements
/// would put a RevenueCat import behind every quota read and make the free-tier rule untestable
/// without the SDK. This facade is the seam instead.
///
/// Named `DocumentAllowance` rather than `ProAccess` because `Features/Library/ProAccess.swift`
/// already owns that name in this module, and answers a *different* question: it is the view-layer
/// read of "is this user Pro", with no notion of the monthly quota.
@MainActor
public struct DocumentAllowance {

    private let entitlements: EntitlementStore
    private let usage: UsageTracker

    public init(entitlements: EntitlementStore, usage: UsageTracker = .shared) {
        self.entitlements = entitlements
        self.usage = usage
    }

    /// Whether the user holds the `pro` entitlement.
    public var isPro: Bool { entitlements.isPro }

    /// Whether another document may be processed right now.
    ///
    /// The entitlement is checked **first** and short-circuits, so a Pro user never touches the
    /// counter and can never be blocked by it — including in the month they upgrade, when the free
    /// allowance is already spent.
    public func canProcessDocument() -> Bool {
        entitlements.isPro || usage.canProcessDocument()
    }

    /// Free documents left this month, or `nil` for a Pro user — for whom the number is meaningless
    /// and displaying it would imply a limit that does not apply.
    public var remainingFreeDocuments: Int? {
        entitlements.isPro ? nil : usage.remainingFreeDocuments
    }

    /// How many documents the free tier allows per calendar month. Forwarded so paywall copy quotes
    /// the same number the gate enforces.
    public var freeMonthlyAllowance: Int { UsageTracker.freeMonthlyAllowance }

    /// When the free allowance resets.
    public var nextResetDate: Date { usage.nextResetDate }

    /// Total documents ever redacted, free or Pro.
    public var lifetimeDocumentCount: Int { usage.lifetimeDocumentCount }

    /// Records one successfully processed document.
    ///
    /// Counted for Pro users too. The counter is also the "you have protected N documents" figure,
    /// and a subscription that lapses should reveal the real month's usage rather than a zero that
    /// silently hands a fresh allowance to anyone who subscribes for a single month.
    public func recordDocumentProcessed() {
        usage.recordDocumentProcessed()
    }
}

public extension EntitlementStore {

    /// Convenience for the common call site: `entitlements.allowance().canProcessDocument()`.
    func allowance(usage: UsageTracker = .shared) -> DocumentAllowance {
        DocumentAllowance(entitlements: self, usage: usage)
    }
}
