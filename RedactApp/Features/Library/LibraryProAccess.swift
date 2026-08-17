import SwiftUI

/// Whether Pro-tier content on the library screens is unlocked.
///
/// The redaction audit log is a Pro feature, so this screen has to ask a question
/// nothing in Phase 2 can answer yet: `Core/Entitlements/**` belongs to the
/// `feature-paywall` agent and does not exist. Rather than reach outside this
/// feature's allowlist or invent a shared entitlement type that would collide with
/// the one Phase 3 declares, the dependency is expressed as a one-bit environment
/// value with a deliberately feature-scoped name.
///
/// Phase 3 wires it in one line at the root:
///
///     .environment(\.libraryProAccess, entitlements.isPro)
///
/// The default is `false`, which is the safe direction: an un-wired build shows the
/// locked state and routes to `AppCoordinator.presentPaywall()`, which already works.
/// It never accidentally gives away a paid feature.
///
/// See `docs/memory/gotchas/library-pro-access-seam.md`.
private struct LibraryProAccessKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `true` when the user holds the `pro` entitlement.
    var libraryProAccess: Bool {
        get { self[LibraryProAccessKey.self] }
        set { self[LibraryProAccessKey.self] = newValue }
    }
}
