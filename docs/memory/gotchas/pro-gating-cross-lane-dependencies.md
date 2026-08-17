---
id: pro-gating-cross-lane-dependencies
date: 2026-08-17
phase: 3
tags: [gotcha, entitlements, scope, paywall]
status: open
---

# Pro gating needs two changes outside the `pro-gating` allowlist

The `pro-gating` agent owns `Features/Export/**`, `Features/Library/**`, `Features/Scan/**`.
Wiring the real entitlement into those screens surfaced two dependencies it may not touch.
Both are logged here per `agent.md` rather than edited.

## 1. `EntitlementStore` must be installed into the environment at the root

`RedactApp/Features/Library/ProAccess.swift` reads:

```swift
@Environment(EntitlementStore.self) private var store: EntitlementStore?
```

Nothing installs it. `RootView` (`RedactApp/App/RootView.swift`) belongs to `scaffold`;
`Core/Entitlements/**` belongs to `feature-paywall`. One of them must add the single line:

```swift
.environment(entitlementStore)
```

alongside the existing `.environment(coordinator)` / `.environment(appEnvironment)` calls.

**Until that line exists the optional resolves to `nil`, which resolves to *not Pro*.** That is the
safe direction — locked states show, paywall routes work, nothing paid is given away, and nothing
crashes. But every user is treated as free, so it is not a state to ship. This is the same failure
mode as the `\.libraryProAccess` key it replaces (see `library-pro-access-seam.md`, now closed):
a seam whose injection step is easy to forget. The optional `@Environment` at least degrades
instead of trapping, which the non-optional form does not.

This also means the three gated screens **will not compile** until `EntitlementStore` exists with
an `isPro: Bool` property. If `feature-paywall` names it differently, `ProAccess.swift` is the only
file to change — that is why the type is named in exactly one place.

## 2. `AppCoordinator.presentPaywall()` takes no context

`RedactApp/Features/Shared/AppRoute.swift` is not in this allowlist. The brief asked that a free
user reaching for a Pro feature be routed to the paywall *with context about which feature they
reached for*, so the subscription screen can lead with the thing they actually wanted.

Today all four call sites — locked PDF format, the general "See what Pro includes" on export,
the locked audit log, and the spent scan quota — call the same argument-less method, so the paywall
cannot distinguish them. Each screen states the context itself in copy next to the button, so
nothing is a dead end and nothing is unexplained; the paywall just cannot personalise.

Suggested shape for whoever owns `AppRoute.swift`:

```swift
public enum PaywallContext: Hashable, Sendable {
    case exportFormat        // reached for multi-page PDF export
    case auditLog            // reached for the redaction audit log
    case monthlyAllowance    // free documents for the month are spent
    case general             // tapped "See what Pro includes"
}

public func presentPaywall(context: PaywallContext = .general)
```

`AppRoute.paywall` would carry the context, and `RouteDestination` would pass it through. Adding a
defaulted parameter keeps every existing call site compiling.
