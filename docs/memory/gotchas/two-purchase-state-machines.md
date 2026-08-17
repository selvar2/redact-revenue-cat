---
id: two-purchase-state-machines
date: 2026-08-17
phase: 3
tags: [gotcha, revenuecat, entitlements, paywall, scope]
status: open
---

# Two purchase state machines exist after the Phase 3 parallel build

`Core/Entitlements/EntitlementStore.swift` (this agent) and `Features/Paywall/PaywallStore.swift`
(the paywall agent, written concurrently) both:

- read `Purchases.shared.customerInfoStream`
- call `purchase(package:)` and `restorePurchases()`
- keep their own `isPro`
- hardcode the entitlement identifier — `RevenueCatConfig.proEntitlementIdentifier` here,
  `PaywallExperiment.entitlementIdentifier` there. Both are the string `"pro"`, so they agree
  today; a change to one and not the other is silent.

## Why this is not currently a bug

Both subscribe to the same push stream, so a purchase made through `PaywallStore` is delivered to
`EntitlementStore` too and the app-wide `isPro` (the one `Features/Library/ProAccess.swift` reads)
becomes true without any coupling between them. Two subscribers to one `AsyncStream` is supported.

## Why it should still be resolved

1. Two definitions of "cancel is not an error" is two places for that rule to rot.
2. `PaywallStore.isPro` and `EntitlementStore.isPro` can be momentarily inconsistent, and a future
   reader cannot tell which one is authoritative.
3. The entitlement identifier is stated twice.

## Recommended fix — integrator or a Phase 3 fixer pass, not this agent

Make `PaywallStore` take the injected `EntitlementStore` and call
`entitlements.purchase(_:)` / `entitlements.restore()` / `entitlements.loadOffering()`, deleting its
own `Purchases` calls and its own `isPro` (`store.isPro` replaces it). The result types
(`PurchaseResult`, `RestoreResult`) already carry exactly the three-way distinction its UI needs,
including `.nothingToRestore`. `PaywallExperiment.entitlementIdentifier` should then forward to
`RevenueCatConfig.proEntitlementIdentifier`.

Both files are outside the other agent's allowlist, which is why neither side merged them
(`CLAUDE.md` rule 8).

**Related:** [[library-pro-access-seam]] [[DEC-004-no-network]]


---

## RESOLVED 2026-08-17 (phase-3 fixer)

`PaywallStore` now takes the injected `EntitlementStore` (`init(context:entitlements:)`) and:

- `isPro` is a computed passthrough to `entitlements.isPro` — the store keeps none of its own
- `purchase(_:)` / `restore()` call `entitlements.purchase(_:)` / `entitlements.restore()` and switch
  on `PurchaseResult` / `RestoreResult`, so `.cancelled` and `.nothingToRestore` stay non-errors
- `observeEntitlementChanges()` is gone: `EntitlementStore` holds the app's single
  `customerInfoStream` subscription, and because it is `@Observable` the paywall's
  `.onChange(of: store.isPro)` sees renewals and cross-device purchases without a second listener
- `PaywallExperiment.entitlementIdentifier` forwards to `RevenueCatConfig.proEntitlementIdentifier`,
  so `"pro"` is written once

`RouteDestination` supplies the store from the environment (optional, with a `@State` fallback, for
the same fail-safe reason `ProAccess` is optional). Only the offering fetch still calls
`Purchases.shared.offerings()` directly, because `EntitlementGateway.currentOffering()` has no
placement-aware form and `PaywallExperiment` needs `offerings.currentOffering(forPlacement:)`.

Observed in the iOS 26.5 simulator: a Test Store 'Test valid purchase' dismissed the paywall and the
Export screen behind it switched to Pro copy — i.e. the purchase and the app-wide gate are now one
fact. `PaywallStore` still has no unit tests of its own; the 11 `EntitlementStore` tests now cover
the machine the paywall actually drives.
