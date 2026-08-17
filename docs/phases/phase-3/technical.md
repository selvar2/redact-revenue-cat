---
id: phase-3-technical
date: 2026-08-17
phase: 3
audience: engineers
tags: [phase-3, technical, revenuecat, entitlements, paywall, pro-gating, storekit]
status: complete
---

# Phase 3 — Technical Record

> Audience: an engineer who has never seen this repo and must be able to rebuild Phase 3 from
> scratch, or resume it cold.
> Siblings: [[phase-3-non-technical]] · [[phase-3-guide-for-kids]]
> Rules that constrain everything below: `CLAUDE.md`. Current state: [[memory-index]].
> Previous phase: [[phase-2-technical]].

## 1. What Phase 3 was for

Phase 2 ended with an app that did the whole job for free, forever, and a placeholder screen
(`FreeTierNoticeView`) standing where the paywall belonged. Phase 3 makes it a product: a
RevenueCat-backed entitlement, a real paywall on two rendering paths, and every Pro feature actually
gated on the entitlement rather than on a constant.

Exit criterion from `plan.md`: *"Test Store purchase flips the entitlement; M3."*

| Lane | Owner agent | Files | What it owns |
|---|---|---|---|
| Entitlements | `entitlements` | `RedactApp/Core/Entitlements/**`, `Tests/EntitlementTests/**` | SDK configuration, the one purchase state machine, the free-tier facade |
| Paywall UI | `paywall-ui` | `RedactApp/Features/Paywall/**` | The screen, both rendering paths, pricing copy, the compliance footer |
| Pro gating | `pro-gating` | `Features/Export/**`, `Features/Library/**`, `Features/Scan/**` | Every place the app says no |

Three builders in parallel with disjoint allowlists, then one verifier pass and one fixer pass — the
bounded loop from [[DEC-005-bounded-loop]]. No agent verified its own work (`CLAUDE.md` rule 7).

**Gate on exit:** `./verify.sh` exit 0 — build succeeded, tests passed, app installs, launches and
stays alive on the simulator. Seven findings from the verifier (four critical/high), nine fixes
applied, three items escalated (§10).

The exit criterion was **observed, not reasoned about**: in the iOS 26.5 simulator, sample →
*Review and export* → *See what Pro includes* rendered Yearly $29.99 (Save 50%, ≈$2.50/mo) and
Monthly $4.99 with Restore Purchases, the auto-renewal sentence and both legal links; *Test valid
purchase* completed, the sheet dismissed itself, and the Export screen switched to Pro copy.
**M3 — first test purchase — end to end.** F10 is `built`, not `verified`: the fixer may not
re-rate its own work (`CLAUDE.md` rule 7).

## 2. Architecture, with real paths

```
RedactApp/
├─ App/
│  ├─ RedactApp.swift          @main — calls RevenueCatConfig.configure() in init()
│  ├─ RouteDestination.swift   case .paywall → RedactPaywallView(context:entitlements:)
│  └─ LegalLinks.swift         privacy / terms / support URLs   ← STILL UNPUBLISHED, §10
├─ Core/Entitlements/
│  ├─ RevenueCatConfig.swift   every key, identifier and the one configure() call
│  ├─ EntitlementGateway.swift the protocol the store talks to + the real pass-through
│  ├─ EntitlementStore.swift   THE purchase state machine — isPro lives here and nowhere else
│  └─ DocumentAllowance.swift  entitlement × free-tier counter, combined once
└─ Features/Paywall/
   ├─ PaywallView.swift        RedactPaywallView — remote path, native fallback, footer under both
   ├─ NativePaywallView.swift  the compiled-in screen, drawn from Token/Typography
   ├─ PaywallStore.swift       screen state only; owns no purchase state
   ├─ PaywallContext.swift     why the paywall appeared → copy + RevenueCat placement id
   ├─ PaywallExperiment.swift  which offering to render (server decides, not us)
   ├─ PaywallPricing.swift     every price/period/legal sentence, derived from StoreProduct
   ├─ PaywallPlanRow.swift     one selectable plan
   ├─ PaywallLegalFooter.swift Restore + Terms + Privacy + auto-renewal sentence
   └─ CustomerCenterView.swift ManageSubscriptionView — built, unreferenced (§10)
```

One-line summary of the shape: **`EntitlementStore` is the only thing in the app that knows whether
you are Pro; everything else asks it.**

## 3. SDK configuration

`RedactApp.init()` is the whole of it:

```swift
@main
struct RedactApp: App {
    init() {
        // The only networking permitted anywhere in this app — CLAUDE.md rule 1, [[DEC-004-no-network]].
        RevenueCatConfig.configure()
    }
    …
}
```

and `RevenueCatConfig.configure()`:

```swift
public static func configure() {
    guard !Purchases.isConfigured else { return }
    Purchases.logLevel = logLevel
    Purchases.configure(with: Configuration.builder(withAPIKey: apiKey).build())
}
```

Four decisions are compressed into those four lines.

**Idempotent by the `isConfigured` guard.** SwiftUI previews and the test bundle both construct the
app type more than once per process. Configuring twice logs a warning and rebuilds the caches for
nothing.

**Before any `Purchases.shared` access, and cheap.** The SDK's first fetch is asynchronous, so this
adds no round trip to launch. Storage bring-up deliberately is *not* here — `AppEnvironment` opens
SwiftData and `RootView` prepares the vault after the first frame.

**No `appUserID`.** RevenueCat generates an anonymous one. Redact has no accounts and collects no
identifiers; answering "No Data Collected" truthfully in App Privacy means never sending the SDK
one.

**Log level is build-dependent** — `.info` in DEBUG so a failed purchase explains itself, `.error`
in release so the SDK is not writing a line per network call into a user's device log.

### 3.1 Why the public SDK key is committed, and why secret keys are categorically different

`RevenueCatConfig.apiKey` is in the repository, in plain text:

```swift
public static let apiKey = "test_RWwnOzDVmDsnnYlBWDqFvzQkzwp"
```

That is deliberate, not laziness, and the reasoning is worth stating precisely because the instinct
"an API key is in the source tree, that is a leak" is usually right and is wrong here.

A **public SDK key** (`test_…` for the Test Store, `appl_…` for the App Store) is shipped inside
every copy of the binary. Anyone can pull it out of an IPA with `strings` in a few seconds. It is
public in exactly the sense a website's publishable Stripe key is public. RevenueCat therefore scopes
it to operations that are harmless coming from an untrusted client:

- reading offerings and products (data you show every user anyway);
- posting a receipt, which RevenueCat then validates **with Apple** before granting anything.

The second half is the load-bearing one. An attacker with the public key can post a receipt. They
cannot post an *entitlement*. The grant comes from Apple's verification of a real transaction, not
from the client's assertion. So there is nothing to steal: treating the key as a secret buys zero
security and costs a keychain dance on every launch, plus a class of "why is the paywall empty on a
fresh install" bugs.

**Secret keys are a different object entirely.** `sk_…` REST keys, the App Store Connect `.p8`, the
Key ID and the Issuer ID can *mint* entitlements, read customer records, and issue refunds — they
speak to the server as the owner of the account, with no Apple receipt in the loop. A leaked `sk_`
key means anyone can grant themselves Pro forever and read every customer's purchase history. None
of them may appear in this repository, in this target, or in any Info.plist (`CLAUDE.md` rule 9),
and `verify.sh` enforces the file-extension half of that mechanically:

```bash
▸ Secret scan (CLAUDE.md rule 9)
  ✓ no key material tracked
```

The operational rule for anyone touching this file: **if the key you are about to paste does not
begin with `test_` or `appl_`, stop.**

Phase 4 swaps the Test Store for the real App Store project by replacing that one line with the
`appl_…` key. Nothing else changes — the entitlement, offering and product identifiers below are
already the production ones.

### 3.2 The identifiers, and why they live in one file

```swift
public static let proEntitlementIdentifier = "pro"
public static let defaultOfferingIdentifier = "default"

public enum ProductIdentifier {
    public static let monthly  = "redact_pro_monthly"
    public static let annual   = "redact_pro_annual"
    public static let lifetime = "redact_pro_lifetime"
}

public enum PackageIdentifier {
    public static let monthly  = "$rc_monthly"
    public static let annual   = "$rc_annual"
    public static let lifetime = "$rc_lifetime"
}
```

Every one of these strings is *also* typed into a dashboard by a human. Two copies in the app is one
copy that can be changed alone and silently stop unlocking anything, so `PaywallExperiment`
forwards rather than restates:

```swift
static var entitlementIdentifier: String { RevenueCatConfig.proEntitlementIdentifier }
```

The product identifiers are deliberately **not** used to build the paywall. They exist for reference
and diagnostics. Prices, currency and billing period must come from `StoreProduct` at runtime (§6).

## 4. The entitlement state machine

`EntitlementStore` is `@Observable`, `@MainActor`, and holds every fact the rest of the app reads:
`isPro`, `customerInfo`, `isLoading`, `lastError`, `currentOffering`, `proExpirationDate`.

Two rules shape all of it.

### 4.1 Never poll

```swift
public func start() {
    guard updatesTask == nil else { return }

    updatesTask = Task { [weak self] in
        guard let self else { return }
        for await info in self.gateway.customerInfoUpdates {
            self.apply(info)
        }
    }

    Task { [weak self] in
        guard let self else { return }
        if let cached = await self.gateway.cachedCustomerInfo() {
            self.apply(cached)
        }
        await self.refresh()
    }
}
```

`customerInfoUpdates` is `Purchases.shared.customerInfoStream`. RevenueCat pushes a new
`CustomerInfo` on renewal, expiry, billing failure, and on a purchase made from another device
signed into the same Apple Account. One subscription, held for the lifetime of the process, means a
subscription that lapses mid-session flips `isPro` without anyone asking — and because the type is
`@Observable`, every view watching it re-renders for free.

Order matters in the second task. The **cache is adopted first**, before the network is consulted,
so a returning Pro user is Pro before the first frame. An app that shows a paywall for half a second
on every cold launch reads as broken.

Both tasks inherit `@MainActor` from the method, so `apply` is a direct call and the published
properties are only ever written on the main actor.

### 4.2 Never fail closed

This is the single most important behaviour in the phase:

```swift
public func refresh() async {
    isLoading = true
    lastError = nil
    defer { isLoading = false }

    do {
        apply(try await gateway.currentCustomerInfo())
    } catch {
        lastError = EntitlementFailure(error)

        // Fail *open*: if the SDK still has a cached answer, use it. If it does not, leave
        // whatever we already had in place rather than revoking access on a timeout.
        if let cached = await gateway.cachedCustomerInfo() {
            apply(cached)
        }
    }
}
```

A network error must never revoke Pro. A paying user on a plane, on a train, or behind a captive
portal keeps everything they paid for. Briefly honouring a subscription that has just expired costs
nothing; locking out a paying customer because a request timed out is a refund request and a
one-star review. `isPro` is only ever cleared when the servers (or the SDK's cache) actually say the
entitlement is inactive.

The distinction is surfaced, not just handled:

```swift
public var isOffline: Bool {
    code == .networkError || code == .offlineConnectionError
}
```

so the paywall can say "you're offline" instead of "purchase failed".

### 4.3 The one place `isPro` is written

```swift
private func apply(_ info: CustomerInfo) {
    customerInfo = info

    let entitlement = info.entitlements.all[entitlementIdentifier]
    isPro = entitlement?.isActive == true
    proExpirationDate = entitlement?.expirationDate
}
```

`entitlements.all[…]?.isActive` rather than `entitlements.active[…]`. `active` filters by
environment; in a sandbox or Test Store build it reports a genuinely-purchased entitlement as
inactive — which would lock the App Review reviewer out of every feature they were asked to check.

### 4.4 Three outcomes, not two

```swift
public enum PurchaseResult: Sendable, Equatable {
    case purchased
    case cancelled
    case failed(EntitlementFailure)
}

public enum RestoreResult: Sendable, Equatable {
    case restoredPro
    case nothingToRestore
    case failed(EntitlementFailure)
}
```

"The user tapped Cancel" and "the payment failed" must not be presented the same way. An error alert
on Cancel is the single most common way a paywall annoys real users — and App Review taps Cancel on
every paywall they see. Both cancellation shapes are handled, because the SDK reports it two ways:

```swift
if outcome.userCancelled { return .cancelled }          // StoreKit 2 path: a flag, not a throw
…
} catch {
    if EntitlementFailure.isUserCancellation(error) { return .cancelled }   // other paths: a throw
```

and a cancellation leaves `lastError` `nil`, so a caller that alerts whenever `lastError != nil`
cannot accidentally scold someone for changing their mind.

`nothingToRestore` is likewise a non-error: someone who never subscribed and taps Restore has done
nothing wrong, and "restore failed" sends them to support for a non-problem.

### 4.5 The gateway seam — why the tests need no network

```swift
public protocol EntitlementGateway: Sendable {
    var customerInfoUpdates: AsyncStream<CustomerInfo> { get }
    func cachedCustomerInfo() async -> CustomerInfo?
    func currentCustomerInfo() async throws -> CustomerInfo
    func restorePurchases() async throws -> CustomerInfo
    func purchase(_ package: Package) async throws -> PurchaseOutcome
    func currentOffering() async throws -> Offering?
}
```

The store's job is a state machine — cached versus fresh, cancelled versus failed, expired versus
offline — and that is exactly the part that must be testable without a network, a StoreKit
configuration file, or a configured SDK (`CLAUDE.md` rule 1 applies to tests too). `RevenueCatGateway`
is the real implementation and every method is a deliberate one-liner, because logic there would be
logic no test can reach.

The one place it is not a bare pass-through is offering lookup, and the fallback is the point:

```swift
public func currentOffering() async throws -> Offering? {
    let offerings = try await Purchases.shared.offerings()
    return offerings.all[RevenueCatConfig.defaultOfferingIdentifier] ?? offerings.current
}
```

### 4.6 `DocumentAllowance` — one question, asked once

```swift
public func canProcessDocument() -> Bool {
    entitlements.isPro || usage.canProcessDocument()
}

public var remainingFreeDocuments: Int? {
    entitlements.isPro ? nil : usage.remainingFreeDocuments
}
```

The entitlement is checked **first** and short-circuits, so a Pro user never touches the counter and
can never be blocked by it — including in the month they upgrade, when the free allowance is already
spent. `remainingFreeDocuments` is `nil` for a Pro user because showing a number would imply a limit
that does not apply.

`UsageTracker` is untouched by design: it lives in `Core/Persistence` and knows nothing about
purchases. Teaching a counter about entitlements would put a RevenueCat import behind every quota
read and make the free-tier rule untestable without the SDK. This facade is the seam instead.

Named `DocumentAllowance` and not `ProAccess` because `Features/Library/ProAccess.swift` already owns
that name and answers a different question — the view-layer read of "is this user Pro", with no
notion of the monthly quota:

```swift
struct ProAccess: DynamicProperty {
    @Environment(EntitlementStore.self) private var store: EntitlementStore?
    @MainActor var isPro: Bool { store?.isPro ?? false }
    @MainActor var exportTier: ExportPipeline.Tier { isPro ? .pro : .free }
}
```

The optional environment read resolves to *not Pro* when nothing installed the store — the safe
direction. This replaced the Phase 2 `\.libraryProAccess` environment key that nobody ever set
([[library-pro-access-seam]]).

## 5. The paywall

### 5.1 Two rendering paths, one behaviour

```swift
@ViewBuilder
private var content: some View {
    if let offering = store.offering, offering.hasPaywall {
        remotePaywall(offering)
    } else {
        NativePaywallView(store: store, usage: usage, onDismiss: { dismiss() })
    }
}
```

**Remote (primary).** When the served offering carries a paywall designed in the dashboard,
`RevenueCatUI.PaywallView` renders it. That is the capability worth having: layout, copy, imagery
and package order change — or get A/B tested — without shipping a build or waiting on App Review.

**Native (fallback).** When the offering has no paywall, or none could be fetched, the screen is
drawn from `Token`/`Typography`. A blank screen because a dashboard was unreachable is a purchase
the user wanted to make and could not.

The type is `RedactPaywallView`, not `PaywallView`: this file imports `RevenueCatUI`, which exports
its own `PaywallView`.

On the remote path the SDK performs the purchase itself, and the app only re-reads the entitlement —
because the entitlement, not the transaction, is what unlocks Pro:

```swift
PaywallView(offering: offering, displayCloseButton: true)
    .onPurchaseCompleted { _ in Task { await store.refreshEntitlement() } }
    .onRestoreCompleted  { _ in Task { await store.refreshEntitlement() } }
    .onPurchaseCancelled { }          // deliberately empty: a cancel is not an error
    .onRequestedDismissal { dismiss() }
```

### 5.2 The required-disclosure block, compiled in under both paths

`PaywallLegalFooter` renders under the remote paywall *and* under the native one. Four things App
Review has documented rejections for — Restore Purchases, the Terms of Use (EULA) link, the Privacy
Policy link, and the auto-renewal sentence — are therefore compiled into the binary rather than
dependent on a dashboard configuration that can be edited after this build ships. A dashboard
mistake can add a second restore button; it can never remove the only one.

```swift
VStack(spacing: Token.Space.sm) {
    SecondaryButton(String(localized: "Restore Purchases", …), systemImage: "arrow.clockwise", …)
        .disabled(isRestoring)

    if let package {
        Text(PaywallPricing.termsSentence(for: package))
            .typeStyle(Typography.caption)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)     // must never truncate
            .frame(maxWidth: Token.Layout.proseWidth)
    }

    HStack(spacing: Token.Space.md) {
        legalLink(String(localized: "Terms of Use", …),   destination: LegalLinks.termsOfUse)
        legalLink(String(localized: "Privacy Policy", …), destination: LegalLinks.privacyPolicy)
    }
    .frame(minHeight: Token.Size.minimumHitTarget)
}
```

The terms sentence is the one string in the app that must never be clipped: no line limit, and
`.fixedSize(horizontal: false, vertical: true)` so it grows down the screen at accessibility text
sizes instead of truncating the words "Renews automatically until cancelled."

`package == nil` (no plans loaded) drops the price sentence rather than inventing one.

Both links open in Safari, out of process — nothing in this app fetches those pages, which keeps
`DEC-004` intact. Which is also why the fact that they currently 404 is a *human* problem and not a
code one (§10).

### 5.3 `PaywallStore` owns no purchase state

```swift
var isPro: Bool { entitlements.isPro }
…
switch await entitlements.purchase(package) {
case .cancelled:            return
case .failed(let failure):  alertMessage = failure.message.isEmpty ? Self.genericFailureMessage : failure.message
case .purchased:
    if isPro {
        justUnlocked = true
    } else {
        // StoreKit succeeded but the entitlement is not active — a deferred/pending purchase
        // (Ask to Buy) or a dashboard product not attached to `pro`.
        alertMessage = Self.pendingMessage
    }
}
```

That `else` branch is the finding-driven part. StoreKit succeeding is not the same as being Pro:
Ask to Buy defers, and a product the dashboard never attached to the `pro` entitlement completes a
purchase that grants nothing. Saying "you're all set" there is a lie the user discovers at the next
locked feature.

The store began the phase as a **second** purchase state machine — its own `customerInfoStream`
subscription, its own `isPro`, its own `purchase()` call ([[two-purchase-state-machines]]). Two
stores each calling `Purchases.purchase` is how a paying user ends up looking un-paid to half the
app. There is now one machine, in `Core`, and this screen reads it.

Unlock is a signal rather than a callback because the same unlock can arrive from three places —
this user's purchase, their restore, or a change pushed to `EntitlementStore` from another device:

```swift
.onChange(of: store.isPro)       { _, isPro    in if isPro { store.markUnlocked() } }
.onChange(of: store.justUnlocked) { _, unlocked in
    guard unlocked else { return }
    // Success is not a screen. The user was mid-task when they hit the wall.
    onUnlocked()
    dismiss()
}
```

`onChange` only fires on a transition, so someone who was already Pro when the screen opened is not
"unlocked" by it.

### 5.4 `PaywallContext` — naming the wall, and the placement seam

```swift
public enum PaywallContext: String, Sendable, CaseIterable, Identifiable {
    case monthlyLimit, pdfExport, auditLog, multiPage, customRules, general
    var placementIdentifier: String { rawValue }
}
```

A paywall that says "Upgrade to Pro" makes the user reconstruct why they were stopped. Naming the
wall — *"You've used your three free documents"* — converts better and is more honest. The raw value
doubles as the RevenueCat **Placement** identifier, so the dashboard can serve a different offering
at the export wall than at the quota wall with no app update.

Call sites, all real:

| Wall | File |
|---|---|
| `.monthlyLimit` | `Features/Scan/ScanView.swift` (two paths) |
| `.pdfExport` | `Features/Export/ExportView.swift` (two paths) |
| `.auditLog` | `Features/Library/DocumentDetailView.swift` |
| computed | `ExportView.swift` — `usage.remainingFreeDocuments > 0 ? .general : .monthlyLimit` |

Everything funnels through the Phase 2 seam, unchanged:

```swift
public func presentPaywall(_ context: PaywallContext = .general) {
    presentedSheet = .paywall(context)
}
```

### 5.5 `PaywallExperiment` — the app makes no decision

```swift
static func offering(from offerings: Offerings, context: PaywallContext) -> Offering? {
    offerings.currentOffering(forPlacement: context.placementIdentifier)
        ?? offerings.current
        ?? offerings[Self.fallbackOfferingIdentifier]
}
```

A resolution order, not a randomiser. A local coin flip would need an app update to change the
split, would not appear in RevenueCat's charts, and would not attribute the two arms to revenue.
`offerings.current` **is** the arm the server bucketed this user into when an experiment is running,
and the SDK reports the impression and any purchase against it automatically. Every step degrades
rather than fails, because a blank screen is a failed purchase.

## 6. Prices are never written down

`PaywallPricing` derives every number from `StoreProduct`. A hardcoded "₹399/month" is wrong in every
storefront but one, and Apple rejects a paywall whose stated price does not match what the App Store
charges.

```swift
static func priceLine(for package: Package) -> String {
    let price = package.storeProduct.localizedPriceString
    guard let period = package.storeProduct.subscriptionPeriod else { return price }
    return String(format: String(localized: "%@/%@", …), price, periodName(period))
}
```

The annual saving badge is computed from the two real prices and refuses to make a claim it cannot
support:

```swift
guard annualProduct.currencyCode == monthlyProduct.currencyCode,
      …
      monthlyRate > 0, annualRate < monthlyRate else { return nil }

let saving = (monthlyRate - annualRate) / monthlyRate * 100
```

`nil` — badge not drawn at all — when the products are in different currencies, when a period is
missing, or when annual is not actually cheaper. A "Save 40%" badge over a plan that now saves 12%
is a false claim on a purchase screen, and dashboard prices can change at any time.

The disclosure sentence adapts to the product rather than being one string:

```swift
static func termsSentence(for package: Package) -> String {
    guard let period = product.subscriptionPeriod else {
        return "… once. This is a one-time purchase, not a subscription: nothing renews and there is
                nothing to cancel."
    }
    let base = "%@ per %@. Renews automatically until cancelled. Cancel any time in Settings, at
                least 24 hours before the period ends."
    guard let intro = product.introductoryDiscount else { return base }
    // .freeTrial → "Free for 7 days, then …"; .payUpFront/.payAsYouGo → "₹99 for the first month, then …"
}
```

Guideline 3.1.2 requires price, billing period and the fact of automatic renewal on the screen where
the purchase happens — not in Settings, not behind a link. Claiming a lifetime purchase renews is as
wrong as omitting renewal from a subscription, so the non-renewing branch says the opposite thing.

`Decimal` arithmetic throughout, and `product.priceFormatter` for the "≈ ₹33 per month" line, so the
per-month breakdown is correct in every currency without a conversion table.

## 7. What must be configured in the RevenueCat dashboard

**This is the part no reader can reconstruct from the code.** The app resolves identifiers; it does
not create them. Until the following exists, `offerings()` returns nothing and every user sees the
native fallback with `unavailable`.

### 7.1 Products

Create three products and attach **all three** to the `pro` entitlement:

| Identifier | Type |
|---|---|
| `redact_pro_monthly` | auto-renewable subscription |
| `redact_pro_annual` | auto-renewable subscription |
| `redact_pro_lifetime` | non-consumable |

Attaching to the entitlement is the step that is silently skippable and produces the exact bug §5.3
handles: the purchase succeeds, `pro` never activates, the user is charged and locked out.

### 7.2 Entitlement

One entitlement, identifier exactly `pro` — matching `RevenueCatConfig.proEntitlementIdentifier`.
Not `Pro`, not `pro_access`. This string is compiled into the binary; a rename in the dashboard
silently stops unlocking anything, everywhere, at once.

### 7.3 Offering

Offering `default`, containing three packages:

| Package identifier | Product |
|---|---|
| `$rc_annual` | `redact_pro_annual` |
| `$rc_monthly` | `redact_pro_monthly` |
| `$rc_lifetime` | `redact_pro_lifetime` |

These are RevenueCat's standard package types and are what `Offering.annual / .monthly / .lifetime`
read. `PaywallStore.displayPackages` builds the screen from those three properties in *our* order —
so a fourth package added in the dashboard cannot rearrange the screen, and a package the dashboard
has not configured is simply absent rather than an empty row (`CLAUDE.md` rule 10).

Mark `default` as **Current**, or `offerings.current` is `nil` and the app falls to step 3 of the
resolution order.

### 7.4 Remote paywall

**Paywalls → Design a paywall**, on the `default` offering. The app renders whatever it is served;
an offering with no paywall gets `NativePaywallView` instead — which is a correct screen, but the
whole point of the remote path is editing copy without a release.

Design it knowing our footer sits underneath it. If the dashboard paywall also carries a restore
button and legal links, that is fine and harmless; missing them is what would not be.

### 7.5 A/B experiment

1. Create a second offering (for example `default_b`) with the **same three package identifiers** and
   a *different paywall design* — the design is the thing being tested. Different package
   identifiers make the arms incomparable.
2. **Experiments → New experiment**: control `default`, treatment `default_b`, 50/50 split, primary
   metric "conversion to `pro`". Start it.

From that moment `offerings.current` returns the bucketed arm per user, sticky across launches, and
purchases are attributed to the arm automatically. No app release is involved in any of it.

Confirming which arm a device is in, from the device, without reading logs:

```swift
static func debugAttribution(for offering: Offering) -> String {
    "offering: \(offering.identifier) · remote paywall: \(offering.hasPaywall ? "yes" : "no")"
}
```

shown only under `#if DEBUG` — an offering identifier is of no use to a user.

### 7.6 Placements (optional)

**Targeting → Placements**: add placements named exactly `monthlyLimit`, `pdfExport`, `auditLog`,
`multiPage`, `customRules`, `general` — the raw values of `PaywallContext` — and point each at an
offering. Until they exist, `currentOffering(forPlacement:)` returns `nil` and the app uses the
experiment's arm, which is the intended default.

### 7.7 Customer Center

Configurable in the dashboard now; `ManageSubscriptionView` wraps `RevenueCatUI`'s Customer Center
but is not yet presented from anywhere in the app (§10).

## 8. Tests

Eleven tests, all driving `EntitlementStore` through a fake gateway. `Purchases` is never
configured and nothing touches the network:

```
testPurchaseTurnsANonProUserIntoAProUser
testUserCancellationIsNotAnError
testThrownCancellationIsAlsoNotAnError
testARealPurchaseFailureIsReported
testRestoreGrantsProWhenThePurchaseExists
testRestoreWithNothingToRestoreIsNotAFailure
testExpiryRevokesPro
testAnExpiryArrivingOnTheStreamFlipsIsPro
testANetworkFailurePreservesCachedPro
testANetworkFailureWithNoCacheKeepsTheStatusAlreadyKnown
testProBypassesTheFreeMonthlyLimit
```

Read that list as a specification. Every case is one that costs money or trust if it is wrong.

The `isPro: false` fixture is an **expired** entitlement, not a missing one, because that is the
shape RevenueCat actually sends after a lapse — a store that checked for mere presence rather than
`isActive` would pass a naive test and grant Pro forever:

```swift
entitlements = [
    Self.entitlementID: EntitlementInfo(
        identifier: Self.entitlementID,
        isActive: false,
        willRenew: false,
        …
        expirationDate: Date(timeIntervalSince1970: 2_000),
        …
    )
]
```

Packages are built with `TestStoreProduct`, RevenueCat's public test initialiser, so a `Package` with
a real price and locale exists without StoreKit.

## 9. Commands — real input, real output

The gate:

```bash
$ ./verify.sh
▸ Toolchain
  ✓ xcodebuild Xcode 26.6
  ✓ python3 3.9.6

▸ Secret scan (CLAUDE.md rule 9)
  ✓ no key material tracked

▸ No-network rule (CLAUDE.md rule 1)
  ✓ no networking outside RevenueCat

▸ Placeholder scan (CLAUDE.md rule 10)
  ✓ no placeholder strings in user-facing code

▸ Build
  ✓ build succeeded

▸ Tests
  ✓ tests passed

▸ Memory layer
  ✓ session log exists for 2026-08-17
  ✓ memory index rebuilt

━━━ GATE PASSED ━━━
$ echo $?
0
```

Test inventory, per file:

```bash
$ for f in $(find Tests -name "*.swift"); do echo "$(grep -c 'func test' $f) $f"; done
2 Tests/DesignSystemTests.swift
11 Tests/DetectionTests/ChecksumTests.swift
6 Tests/DetectionTests/NameDetectorTests.swift
13 Tests/DetectionTests/ClassifierGeometryTests.swift
6 Tests/DetectionTests/BankAccountTests.swift
0 Tests/DetectionTests/DetectionFixtures.swift
16 Tests/DetectionTests/PatternDetectorTests.swift
11 Tests/DetectionTests/FalsePositiveTests.swift
8 Tests/DetectionTests/LabelledFieldDetectorTests.swift
9 Tests/PersistenceTests/DocumentStoreTests.swift
7 Tests/ExportTests/AnnotationAuditTests.swift
11 Tests/EntitlementTests/EntitlementStoreTests.swift
4 Tests/RedactionTests/SampleDocumentLeakTests.swift
11 Tests/RedactionTests/IrreversibilityTests.swift
$ grep -rn "func test" Tests | wc -l
     115
```

Confirming the app never opens a socket outside the SDK — the rule the whole privacy claim rests on:

```bash
$ grep -rn --include='*.swift' -E 'URLSession|URLRequest|NWConnection|CFNetwork' RedactApp | grep -vi revenuecat
$ echo $?
1
```

Every paywall entry point, enumerated from source rather than from memory:

```bash
$ grep -rn "presentPaywall" --include='*.swift' RedactApp
RedactApp/Features/Shared/AppRoute.swift:144:    public func presentPaywall(_ context: PaywallContext = .general) {
RedactApp/Features/Scan/ScanView.swift:179:                coordinator.presentPaywall(.monthlyLimit)
RedactApp/Features/Scan/ScanView.swift:376:            coordinator.presentPaywall(.monthlyLimit)
RedactApp/Features/Export/ExportView.swift:94:                    coordinator.presentPaywall(failure.paywallContext)
RedactApp/Features/Export/ExportView.swift:222:                    coordinator.presentPaywall(.pdfExport)
RedactApp/Features/Export/ExportView.swift:244:                coordinator.presentPaywall(.pdfExport)
RedactApp/Features/Export/ExportView.swift:317:                    coordinator.presentPaywall(usage.remainingFreeDocuments > 0 ? .general : .monthlyLimit)
RedactApp/Features/Library/DocumentDetailView.swift:295:                coordinator.presentPaywall(.auditLog)
```

The three legal URLs, the one command that has not yet returned what it must:

```bash
$ curl -sI https://selvar2.github.io/redact-revenue-cat/privacy.html | head -1
# must print: HTTP/2 200        ← not yet true; see §10
```

## 10. What is incomplete — read this before trusting the phase

**The App Review checklist has not been walked.** The disclosure block is compiled in and correct by
inspection, but nobody has gone through Guideline 3.1.2 line by line against the built screen. That
is a Phase 5 task and it is not done.

**The restore button and the legal links have not been exercised on a device.** They are wired,
rendered and reachable in the simulator; nobody has tapped Restore against an Apple Account with a
real purchase, and nobody can meaningfully tap the links while they 404.

Three items were escalated rather than fixed:

1. **The legal URLs are still unpublished.** `https://selvar2.github.io/redact-revenue-cat/{privacy,
   terms,support}.html` — none published, none verifiable from this machine. Terms of Use and Privacy
   Policy are now live, tappable links **on the paywall**, so a 404 is both a metadata-validation
   failure at submission and a reviewer-facing rejection at review. A human must publish the three
   pages and confirm HTTP 200 on each before F13. Tracked in [[legal-urls-not-published]] (the host
   in that file was corrected this phase to match `LegalLinks.swift`, which is authoritative).
2. **`PaywallStore` has no unit tests of its own.** The eleven `EntitlementStore` tests cover the
   state machine it drives, which is the part that costs money. Adding a `PaywallStore` test target
   and a fake was outside the findings' suggested fixes, so it was flagged rather than done.
3. **`ManageSubscriptionView` is unreferenced.** The Customer Center wrapper is built and correct;
   no finding asked for it, and where a manage-subscription entry point belongs — About? Library? —
   is a product decision, not a fixer decision.

## 11. Failure modes worth knowing

| Symptom | Cause | Where |
|---|---|---|
| Paywall shows the native screen with "We couldn't load the plans" | No offering marked Current, or none configured | §7.3 |
| Purchase completes, user still not Pro | Product not attached to the `pro` entitlement | §7.1; handled at §5.3 |
| Everyone is suddenly not Pro | Entitlement renamed in the dashboard | §7.2 |
| Pro user locked out on a flaky connection | Would mean §4.2 was broken | `refresh()` |
| Reviewer reports "purchase failed" after tapping Cancel | Would mean the three-outcome enum collapsed to two | §4.4 |
| Sandbox purchase reads as inactive | `entitlements.active` used instead of `.all[…].isActive` | §4.3 |
| Price on screen ≠ price charged | A literal crept into the UI | §6 |

## 12. How to replicate this phase from scratch

1. Add the RevenueCat SPM package; import `RevenueCat` and `RevenueCatUI`.
2. Write `RevenueCatConfig` first — one file that names every key and identifier. Call `configure()`
   from `@main init()`, guarded by `Purchases.isConfigured`.
3. Define the gateway protocol **before** the store. It is what makes the rest testable.
4. Write `EntitlementStore` against the protocol: adopt the cache first, subscribe to the stream,
   never poll, never revoke on a network error, and write `isPro` in exactly one function.
5. Write the eleven tests against a fake gateway before wiring any UI. Cancel-is-not-an-error and
   offline-preserves-Pro are the two that justify the whole design.
6. Build the paywall as a screen with no purchase state: it renders, it delegates, it dismisses.
7. Render the compliance footer yourself, under both paths.
8. Derive every price and every legal sentence from `StoreProduct`. Never type a number.
9. Gate features on the entitlement through one facade (`DocumentAllowance`) and one view property
   (`ProAccess`), so no feature ever combines the entitlement and the quota by hand.
10. Configure the dashboard (§7) — the app is inert without it.
