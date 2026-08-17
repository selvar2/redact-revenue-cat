---
id: DEC-007-apple-key-types
date: 2026-08-17
phase: 4
tags: [decision, security, appstore, revenuecat]
status: accepted
---

# DEC-007 — Apple's two `.p8` key types, and why the existing one could not be reused

## The question

The developer had `AuthKey_CDCMHRBW3C.p8` from an earlier TestFlight setup and asked whether it
could be reused for RevenueCat instead of generating a new key.

## Decision

**No.** It is an App Store Connect API key; RevenueCat's required slot needs an **In-App Purchase**
key. A new one was generated (`BU27GRYDV3`).

## Why this is a trap rather than a technicality

Both are ES256 private keys in identical PEM envelopes. `openssl pkey -noout -text` reports
`Private-Key: (256 bit)` for either. **Nothing inside the file identifies its type.** The only
signals are Apple's filename prefix and which page you downloaded it from.

| | App Store Connect API | In-App Purchase |
|---|---|---|
| Filename | `AuthKey_*.p8` | `SubscriptionKey_*.p8` |
| Tab | Integrations → App Store Connect API | Integrations → In-App Purchase |
| Grants | apps, builds, TestFlight, metadata, users, finance | Apple authenticating purchase validation |
| Consumed by | `asc` CLI | RevenueCat, App Store Server API |
| Roles | Admin / App Manager / Developer / … | none — purpose-built |

**The failure mode is silence.** From RevenueCat's own upload form:

> When using Purchases v5.x+ (i.e., StoreKit 2), transactions will fail to be recorded without this
> key being set. This can result in users not accessing the purchases they are entitled to.

The wrong key does not throw. It ships an app where **customers pay and receive nothing** — visible
only as support tickets, never as a crash or a log line. That is why this was checked rather than
assumed, and why it earned a decision record instead of a passing note.

## The old key is not useless

RevenueCat has a **second, optional** slot for an App Store Connect API key — product import and
automatic price-change sync. `CDCMHRBW3C` fits it exactly, and the `asc` CLI needs it for Phase 5
TestFlight uploads regardless.

**It was deliberately not uploaded.** It had been pasted into a chat transcript and carries **Admin**
scope. Propagating a credential already treated as exposed into another system is the wrong order of
operations.

## Recommended, awaiting the human

1. Revoke `CDCMHRBW3C`
2. Regenerate scoped to **App Manager**, not Admin — it only needs to upload builds and edit metadata
3. Upload the replacement to RevenueCat's optional slot, and `asc login` with it

Not done unilaterally: the key is named "TestFlight Upload" and was last used 2026-07-18, so
something of the developer's may depend on it. Breaking another project's CI is not an agent's call.

## Rule of thumb worth keeping

> Two credentials that look identical and do different jobs are a landmine. Check the filename and
> the source page before use — it costs two minutes and prevents a class of bug that never announces
> itself.

**Related:** [[DEC-004-no-network]] · [[phase-4-technical]]
