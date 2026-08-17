---
id: paywall-wiring-outside-allowlist
date: 2026-08-17
phase: 3
tags: [gotcha, paywall, scope, revenuecat]
status: open
---

# The real paywall exists, but three lines that connect it live outside `feature-paywall`'s scope

`feature-paywall`'s allowlist for this run was `RedactApp/Features/Paywall/**` only. The paywall,
the Customer Center wrapper and the experiment seam are built and parse clean, but the app still
shows the Phase 2 placeholder until someone with `RedactApp/App/**` in scope applies the following.
None of it is a design decision — it is mechanical wiring, deliberately left undone rather than
committed as a scope violation (`CLAUDE.md` rule 8).

## 1. `RedactApp/App/RouteDestination.swift` — swap the placeholder

```swift
// was
case .paywall: FreeTierNoticeView()

// now
case .paywall: RedactPaywallView(context: .monthlyLimit)
```

The type is `RedactPaywallView`, not `PaywallView`: `Features/Paywall/PaywallView.swift` imports
`RevenueCatUI`, which exports its own `PaywallView`, and a same-named app type would shadow it.

## 2. `RedactApp/App/FreeTierNoticeView.swift` — delete the file

Its own doc comment says Phase 3 deletes it. It cannot ship alongside the real paywall: two screens
explaining the same limit, one of which cannot sell anything, is exactly the placeholder
`CLAUDE.md` rule 10 forbids. After deleting, run `xcodegen generate`.

## 3. `RedactApp/App/RedactApp.swift` — configure the SDK before any paywall is presented

```swift
Purchases.configure(withAPIKey: "test_RWwnOzDVmDsnnYlBWDqFvzQkzwp")
```

`PaywallStore` guards every call with `Purchases.isConfigured` and degrades to an explanatory
screen with a working Restore button rather than crashing, so the order of operations is safe — but
until this line exists no purchase can be made.

## 4. `AppCoordinator.presentPaywall()` carries no context

`presentPaywall()` takes no argument, so every wall currently renders `PaywallContext.monthlyLimit`.
The contextual copy — "Export as PDF with Pro", "See exactly what was removed" — only appears once
the seam widens:

```swift
public func presentPaywall(_ context: PaywallContext = .monthlyLimit) { … }
```

`Features/Shared/AppRoute.swift` is the contract agent's file, not the paywall agent's. Until then
the PDF-export and audit-log walls are reachable in code and correct, but never shown with their own
copy.

## 5. `\.libraryProAccess` still defaults to `false`

[[library-pro-access-seam]] asked for one line in `RootView`. The paywall does not declare an
app-wide entitlement type (that would collide with whatever `Core/Entitlements/**` declares), so
whoever owns that module should feed it, reading the entitlement identifier from
`PaywallExperiment.entitlementIdentifier` (`"pro"`) rather than restating the string.

**Related:** [[library-pro-access-seam]] [[legal-urls-not-published]]


---

## RESOLVED 2026-08-17 (phase-3 fixer, which had `RedactApp/App/**` in scope)

1. `RouteDestination` resolves `case .paywall(let context)` to
   `RedactPaywallView(context:entitlements:)`.
2. `RedactApp/App/FreeTierNoticeView.swift` is deleted; `xcodegen generate` re-run.
3. The SDK was already configured — `RedactApp.swift` calls `RevenueCatConfig.configure()`.
4. `AppRoute.paywall` now carries a `PaywallContext` and `AppCoordinator.presentPaywall(_:)` takes
   one (defaulting to `.general`). All six call sites pass the wall they are actually at.
5. The `\.libraryProAccess` seam was already replaced by `ProAccess` reading `EntitlementStore`
   from the environment, which `RootView` installs.
