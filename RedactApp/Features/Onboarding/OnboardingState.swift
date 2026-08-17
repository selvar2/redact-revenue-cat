import Foundation
import Observation

/// Whether the first-run explainer has been seen.
///
/// Deliberately **not** `UsageTracker`. That type answers "how much of the free tier is left this
/// month" and its storage resets on a monthly boundary; "has this person been introduced to the
/// app" must survive forever and has nothing to do with entitlements. Sharing the store would mean
/// a quota reset re-introducing the app to a paying user.
///
/// `UserDefaults` rather than SwiftData: this is a single boolean that must be readable before the
/// model container is touched, and it should not be part of the data a user can "delete all" away —
/// re-showing onboarding after a library wipe would read as the app forgetting them.
@Observable
@MainActor
public final class OnboardingState {

    private enum Key {
        /// Versioned so a materially different onboarding in a later release can be shown again to
        /// existing users by bumping the suffix, without inventing a migration.
        static let completed = "onboarding.completed.v1"
    }

    public static let shared = OnboardingState()

    private let defaults: UserDefaults

    /// True once the user has finished or skipped the explainer.
    public private(set) var hasCompleted: Bool

    /// - Parameter defaults: injectable so tests can run against an isolated suite rather than the
    ///   process-wide store.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompleted = defaults.bool(forKey: Key.completed)
    }

    /// Records that onboarding is done. Idempotent.
    public func complete() {
        guard !hasCompleted else { return }
        hasCompleted = true
        defaults.set(true, forKey: Key.completed)
    }

    /// Shows the explainer again. Reachable from About, so a user who skipped on day one is not
    /// locked out of the explanation of what the app actually guarantees.
    public func reset() {
        hasCompleted = false
        defaults.removeObject(forKey: Key.completed)
    }
}
