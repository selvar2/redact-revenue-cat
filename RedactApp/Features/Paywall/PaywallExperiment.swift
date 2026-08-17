import Foundation
import RevenueCat

/// Decides **which offering the paywall renders** — and deliberately contains no decision of its own.
///
/// The variant a user sees is chosen by RevenueCat's server (Experiments and Targeting), not by this
/// app. That is the whole point: a local coin flip would need an app update to change the split, it
/// would not be reflected in RevenueCat's charts, and the two arms would not be attributed to
/// revenue. So the rule here is a resolution order, not a randomiser:
///
/// 1. **Placement** for this paywall's context (`monthlyLimit`, `pdfExport`, …), when the dashboard
///    has one configured. Lets the quota wall and the export wall run different offerings.
/// 2. **`offerings.current`** otherwise — this is the value the server already personalised. When an
///    experiment is running, `current` *is* the arm this user was bucketed into, and the SDK reports
///    the impression and any purchase against it automatically.
/// 3. The offering literally named `default`, as a last resort, so a misconfigured dashboard shows a
///    real paywall rather than nothing.
///
/// A blank screen because a dashboard was unreachable is a failed purchase, so every step degrades
/// rather than fails.
///
/// ## What a human must configure for the A/B test to actually run
///
/// Nothing in this file changes. In the RevenueCat dashboard:
///
/// 1. **Products** — create `redact_pro_monthly`, `redact_pro_annual`, `redact_pro_lifetime` and
///    attach all three to the `pro` entitlement.
/// 2. **Offering `default`** — packages `$rc_monthly`, `$rc_annual`, `$rc_lifetime`. This is the
///    control arm and the fallback in step 3 above.
/// 3. **A second offering** (for example `default_b`) with the same three packages and a *different
///    paywall design* — that is the thing being tested. Same package identifiers, or the two arms
///    are not comparable.
/// 4. **Paywalls → Design a paywall** on *both* offerings. The app renders whichever it is served;
///    an offering with no paywall falls back to the native screen in ``NativePaywallView``.
/// 5. **Experiments → New experiment**: control `default`, treatment `default_b`, traffic split
///    50/50, primary metric "conversion to `pro`". Start it. From that moment `offerings.current`
///    returns the bucketed arm per user, sticky across launches.
/// 6. *(Optional, for step 1 of the resolution order)* **Targeting → Placements**: add placements
///    named exactly `monthly_limit`… — the raw values of ``PaywallContext`` — and point each at an
///    offering. Until those exist, `currentOffering(forPlacement:)` returns `nil` and the app uses
///    the experiment's arm, which is the intended default.
///
/// No app release is needed for any of the above.
enum PaywallExperiment {

    /// The offering RevenueCat's server chose for this user, for this context.
    ///
    /// - Parameters:
    ///   - offerings: the payload from `Purchases.shared.offerings()`.
    ///   - context: why the paywall is being shown; supplies the placement identifier.
    static func offering(from offerings: Offerings, context: PaywallContext) -> Offering? {
        offerings.currentOffering(forPlacement: context.placementIdentifier)
            ?? offerings.current
            ?? offerings[Self.fallbackOfferingIdentifier]
    }

    /// The offering identifier configured in the dashboard as the control arm.
    ///
    /// Used only when the server returned no current offering at all — a misconfiguration. It is not
    /// the normal path, and reaching it is worth noticing in the dashboard's charts.
    static let fallbackOfferingIdentifier = "default"

    /// The entitlement that unlocks Pro. Forwards to ``RevenueCatConfig`` rather than restating the
    /// literal: the identifier is typed into the dashboard by a human, and two copies of it in the
    /// app is one copy that can be changed alone and silently stop unlocking anything.
    static var entitlementIdentifier: String { RevenueCatConfig.proEntitlementIdentifier }

    /// A one-line, non-user-facing description of which arm was served.
    ///
    /// Shown only in `#if DEBUG` builds, on the paywall itself, so that whoever is running the
    /// experiment can confirm from a device which arm they are in without reading logs. It must
    /// never ship visibly: a user has no use for an offering identifier.
    static func debugAttribution(for offering: Offering) -> String {
        "offering: \(offering.identifier) · remote paywall: \(offering.hasPaywall ? "yes" : "no")"
    }
}
