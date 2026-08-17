import SwiftUI

/// The single question the feature layer is allowed to ask about a subscription:
/// *does this user hold the `pro` entitlement right now?*
///
/// It is a `DynamicProperty`, so a view declares it as a plain stored property and
/// SwiftUI keeps the nested `@Environment` read up to date:
///
///     private var proAccess = ProAccess()
///     …
///     if proAccess.isPro { … }
///
/// **Why one type instead of four `@Environment` reads.** `EntitlementStore` belongs to
/// `Core/Entitlements/**`, which is the `feature-paywall` agent's lane. Scan, Export and
/// Library all need the answer. Naming the entitlement type in one file rather than in
/// every screen means a rename over there is a one-line change here, and no feature ever
/// learns that RevenueCat exists (`CLAUDE.md` rule 1 keeps the SDK behind that boundary).
///
/// It lives in `Features/Library/` because this is where the seam was first declared, as
/// `\.libraryProAccess`, which it replaces. That environment key had no one setting it, so
/// every user — paying or not — saw the locked audit log
/// (`docs/memory/gotchas/library-pro-access-seam.md`). Reading the store directly removes
/// the injection step that was being forgotten.
///
/// **The optional is load-bearing.** `@Environment(EntitlementStore.self)` in its
/// non-optional form traps at runtime when nothing installed the store. The optional form
/// yields `nil`, which resolves to *not Pro* — the safe direction. A build that forgot the
/// root injection shows locked states and working paywall routes; it never gives a paid
/// feature away, and it never crashes on a screen the user was already using.
struct ProAccess: DynamicProperty {

    @Environment(EntitlementStore.self) private var store: EntitlementStore?

    /// `true` only when the entitlement layer is present *and* reports the `pro` entitlement.
    @MainActor var isPro: Bool { store?.isPro ?? false }

    /// The same fact in the shape `ExportPipeline` wants.
    @MainActor var exportTier: ExportPipeline.Tier { isPro ? .pro : .free }
}
