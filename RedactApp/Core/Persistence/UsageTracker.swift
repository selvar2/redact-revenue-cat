import Foundation
import Observation

/// Free-tier quota: how many documents the user has processed this calendar month.
///
/// Free tier is **3 documents per calendar month**. The quota resets on the first of
/// the month rather than on a rolling 30-day window because "3 a month" is what the
/// paywall says, and a rolling window would make the counter appear to reset on a
/// date the user cannot predict.
///
/// Storage is `UserDefaults`, not SwiftData: this is one small key that must be
/// readable before the model container is open, and it must survive a "delete all
/// documents" purge — otherwise clearing the library would hand out a free reset.
///
/// This is a *usage* counter only. It knows nothing about entitlements, purchases,
/// or RevenueCat; the paywall layer combines this with the user's Pro status.
@MainActor
@Observable
public final class UsageTracker {

    /// Documents a free user may process per calendar month.
    nonisolated public static let freeMonthlyAllowance = 3

    /// Shared instance backed by `UserDefaults.standard`.
    public static let shared = UsageTracker()

    private enum Key {
        static let period = "usage.currentPeriod"
        static let count = "usage.documentsThisPeriod"
        static let lifetime = "usage.documentsLifetime"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar

    /// Injected so tests can pin "now" without waiting for a month boundary.
    private let now: @Sendable () -> Date

    public init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Reading

    /// Documents processed in the current calendar month.
    public var documentsThisMonth: Int {
        guard defaults.string(forKey: Key.period) == currentPeriodKey else { return 0 }
        return defaults.integer(forKey: Key.count)
    }

    /// Free documents left this month, floored at zero.
    ///
    /// Pro users are unlimited; this value is meaningless for them and the paywall
    /// layer should not display it.
    public var remainingFreeDocuments: Int {
        max(0, Self.freeMonthlyAllowance - documentsThisMonth)
    }

    /// Whether a *free-tier* user may process another document right now.
    public func canProcessDocument() -> Bool {
        remainingFreeDocuments > 0
    }

    /// Total documents ever processed. Drives the "you've protected N documents"
    /// line in settings, and is never reset by the monthly rollover.
    public var lifetimeDocumentCount: Int {
        defaults.integer(forKey: Key.lifetime)
    }

    /// First instant of the next calendar month — the moment the quota resets.
    /// The paywall shows this so an out-of-quota user knows exactly when they are
    /// not stuck, which is the difference between a dead end and a choice.
    public var nextResetDate: Date {
        let start = calendar.dateInterval(of: .month, for: now())?.start ?? now()
        return calendar.date(byAdding: .month, value: 1, to: start) ?? start
    }

    // MARK: - Writing

    /// Records one processed document. Call **after** the redaction succeeds, so a
    /// failed run never consumes quota.
    public func recordDocumentProcessed() {
        rollPeriodIfNeeded()
        defaults.set(defaults.integer(forKey: Key.count) + 1, forKey: Key.count)
        defaults.set(defaults.integer(forKey: Key.lifetime) + 1, forKey: Key.lifetime)
    }

    /// Discards the current month's usage. Exists for the test suite and for a
    /// support-initiated reset; no user-facing control calls it.
    public func resetCurrentPeriod() {
        defaults.set(currentPeriodKey, forKey: Key.period)
        defaults.set(0, forKey: Key.count)
    }

    // MARK: - Period bookkeeping

    /// `"2026-08"`. Sortable, human-readable in a defaults dump, and stable across
    /// locales because the components come from the calendar, not a formatter.
    private var currentPeriodKey: String {
        let components = calendar.dateComponents([.year, .month], from: now())
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }

    private func rollPeriodIfNeeded() {
        let key = currentPeriodKey
        guard defaults.string(forKey: Key.period) != key else { return }
        defaults.set(key, forKey: Key.period)
        defaults.set(0, forKey: Key.count)
    }
}
