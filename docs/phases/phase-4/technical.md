---
id: phase-4-technical
date: 2026-08-17
phase: 4
tags: [phase-doc, technical, appstore, revenuecat, milestone-4]
status: complete
audience: engineers
---

# Phase 4 — Technical

> Connecting the app to the **real** App Store. Milestone 4 achieved.
> Plain-language version: [[phase-4-non-technical]] · For a 10-year-old: [[phase-4-guide-for-kids]]

## What this phase did

Phase 3 could take money from a *simulated* store. Phase 4 pointed the same code at Apple's real
one. No feature changed. One string changed.

```diff
- public static let apiKey = "test_RWwnOzDVmDsnnYlBWDqFvzQkzwp"
+ public static let apiKey = "appl_DuknWVjObDvejcuDZURluQLtfDS"
```

That the phase was one line is the *result* of a Phase 3 decision, not luck: every RevenueCat
constant lives in `RedactApp/Core/Entitlements/RevenueCatConfig.swift`, and the entitlement,
offering and product identifiers were production values from day one. The Test Store never had its
own identifiers to migrate away from.

## The headline: two Apple keys that look identical and are not

The user supplied an existing `.p8` from an earlier TestFlight setup and asked whether it could be
reused. It could not, and the reason is worth internalising because **the failure mode is silent**.

| | App Store Connect API key | In-App Purchase key |
|---|---|---|
| Filename | `AuthKey_XXXXXXXXXX.p8` | `SubscriptionKey_XXXXXXXXXX.p8` |
| Created at | Users and Access → Integrations → **App Store Connect API** | … → **In-App Purchase** |
| Grants | Manage apps, builds, TestFlight, metadata, users, finance reports | Apple authenticating purchase-validation requests |
| Used by | the `asc` CLI | RevenueCat, App Store Server API |
| Scope model | Roles (Admin / App Manager / Developer …) | No roles — purpose-built |
| We had | ✅ `CDCMHRBW3C`, **Admin** | ❌ **Active (0)** |

Both are ES256 private keys in identical PEM envelopes. `openssl pkey` reports
`Private-Key: (256 bit)` for either. **Nothing in the file itself tells you which is which** — only
Apple's filename prefix and the page you downloaded it from.

Why it matters, in RevenueCat's own words on the upload form:

> When using Purchases v5.x+ (i.e., StoreKit 2), transactions will fail to be recorded without this
> key being set. This can result in users not accessing the purchases they are entitled to.

So the wrong key does not throw. It produces **customers who pay and receive nothing** — the worst
class of bug a paid app can ship, and one that surfaces as support tickets rather than as a crash.

### How to check, in one command

```bash
$ ls ~/Downloads/*.p8
AuthKey_CDCMHRBW3C.p8          # App Store Connect API
SubscriptionKey_BU27GRYDV3.p8  # In-App Purchase
```

Apple's own naming is the reliable signal. Confirm against App Store Connect → Users and Access →
Integrations, where each key type has its own tab and its own **Active (n)** count.

## What was created

```
Apple Developer
  Team ID                  8837BPRM4M
  Bundle ID                com.senthilnathanraja.redact          (explicit App ID)

App Store Connect
  App ID                   6802355309
  Name                     "Redact: Hide Personal Info"
  SKU                      REDACT-IOS-2026
  Subscription group       "Redact Pro"  (22315273)   ← still empty, see Known gaps
  In-App Purchase key      BU27GRYDV3
  Issuer ID                34fe7ae7-f498-44e2-82ae-a34c1e95e7d7

RevenueCat
  App Store app            app8a75e71942  "Redact (App Store)"
  Public SDK key           appl_DuknWVjObDvejcuDZURluQLtfDS
```

### Order of operations matters

The App Store Connect **New App** dialog silently refuses to open if no bundle ID is registered. It
does not say so. Register the App ID first:

*developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → + → App IDs → App →
Explicit.* No capabilities need enabling — In-App Purchase is on by default for every App ID, and
camera/photo access is governed by `Info.plist` purpose strings, not by capabilities.

## Verification — from the device log, not from optimism

A green build proves nothing about which store you are talking to. The evidence is StoreKit traffic:

```bash
$ xcrun simctl launch "iPhone 17 Pro" com.senthilnathanraja.redact
$ xcrun simctl spawn "iPhone 17 Pro" log show --last 60s \
    --predicate 'processImagePath CONTAINS "RedactApp"' | grep -i storekit
```

```
RedactApp: (StoreKit) [SKPaymentQueue] Adding storefront listener
RedactApp: (StoreKit) [91e00123_SK1] Starting new storefront update task
RedactApp: (StoreKit) Storefront updated to StorefrontInternal(id: "143441,29", countryCode: "USA")
RedactApp: (StoreKit) StoreKit/TransactionUpdateStart
RedactApp: (StoreKit) StoreKit/TransactionQuery
RedactApp: (StoreKit) StoreKit/PurchaseIntentCheck
```

Under the Test Store key **none of this appeared** — Test Store purchases are simulated and bypass
StoreKit entirely. A real `SKPaymentQueue`, a resolved storefront and a transaction query *are*
the "first Store API call" the milestone names.

Server-side confirmation: RevenueCat's onboarding checklist advanced **3 of 6 → 4 of 6**, with
*"Create a real app configuration"* completing.

## Secret handling

The `.p8` never entered the repository, and the plan never relied on `.gitignore` to keep it out.

- Downloaded to `~/Downloads` (outside any git working tree)
- Copied to the **session scratchpad** only because the browser upload tool reads solely
  session-allowed paths; `chmod 600`; deleted immediately after upload
- `*.p8` is the **first line** of `.gitignore` — a backstop, not the strategy
- `verify.sh` step 2 fails the gate if any `.p8`/`.p12`/`.cer`/`.mobileprovision` becomes tracked

Pre-push sweep before publishing to the public repo:

```bash
$ git ls-files -z | xargs -0 grep -InE 'BEGIN [A-Z ]*PRIVATE KEY|MIG[A-Za-z0-9+/]{20,}'
  NONE ✓
$ git ls-files | grep -Ei '\.p8$'
  no .p8 tracked ✓
```

### The public SDK key is committed, deliberately

`appl_…` and `test_…` keys ship inside every copy of the binary. Anyone can extract one from an IPA
with `strings` in seconds, which is why RevenueCat scopes them to operations that are harmless from
an untrusted client: reading offerings, and posting receipts the servers validate with Apple anyway.
Treating it as a secret buys nothing and costs a keychain dance on every launch.

`sk_…` REST keys, the `.p8`, the Key ID and the Issuer ID are categorically different — they can
mint entitlements and read customer data. `RevenueCatConfig.swift` states this in a doc comment
where the next person will actually read it:

> If you are about to paste a key that does not begin with `test_` or `appl_`, stop.

## Automating App Store Connect — two traps

Both cost real time; both are now in [[gotcha-asc-form-automation]].

**1. Native `<select>` popups render outside the page.** Synthetic clicks and key events never reach
them, and setting `.value` directly leaves React unaware — the field visually reverts to "Choose"
and reports *"This field is required"*. What works is the native prototype setter plus real events:

```js
const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value').set;
setter.call(el, 'com.senthilnathanraja.redact');
el.dispatchEvent(new Event('input',  { bubbles: true }));
el.dispatchEvent(new Event('change', { bubbles: true }));
```

**2. Coordinate clicks are unreliable on App Store Connect.** The page re-renders at varying zoom
between screenshots, so a coordinate captured in one frame lands elsewhere in the next. Clicking by
**element reference** succeeded every time coordinates failed. Prefer refs on this site.

## Known gaps leaving Phase 4

| Gap | Impact |
|---|---|
| Subscription products not created in App Store Connect | Group `22315273` exists but is empty. **No sandbox purchase can succeed until this is done.** Next task |
| No remote paywall configured | Native fallback renders; the remote-configured paywall is the HAMM-award capability |
| `CDCMHRBW3C` still active, Admin-scoped, and was pasted into a chat transcript | Recommended: revoke, regenerate as **App Manager**. Needed for Phase 5 TestFlight uploads regardless |
| Five other Admins on the developer account | Each can see this app, upload builds, change pricing, read financial reports. Flagged to the human; not an agent's decision |

## Reproducing this phase from scratch

1. Register an explicit App ID at *developer.apple.com → Identifiers*. **Do this first** or the New
   App dialog will not open.
2. *App Store Connect → Apps → + → New App*: platform iOS, unique name (≤30 chars, reserved 180
   days), primary language, the bundle ID from step 1, any unique SKU.
3. *Users and Access → Integrations → **In-App Purchase** → Generate*. Download the
   `SubscriptionKey_*.p8` — **downloadable exactly once**. Copy the Key ID and the Issuer ID.
4. *RevenueCat → Apps → New app configuration → App Store*: name, bundle ID, upload the `.p8`
   (Key ID auto-fills), paste the Issuer ID, Save. Confirm it reads **"Valid credentials"**.
5. Reveal the app's **Public API Key** (`appl_…`) and put it in `RevenueCatConfig.apiKey`.
6. Build, install, launch, and read the log for `SKPaymentQueue` + a resolved storefront.

**Related:** [[phase-3-technical]] · [[DEC-004-no-network]] · [[gotcha-asc-form-automation]]
