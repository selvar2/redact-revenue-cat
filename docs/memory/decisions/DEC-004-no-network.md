---
id: DEC-004-no-network
date: 2026-08-17
phase: 0
tags: [decision, privacy, app-review, architecture]
status: accepted
---

# DEC-004 — Zero network calls, except the RevenueCat SDK

## Decision

The app makes **no** network requests. The single permitted exception is the RevenueCat SDK, which
needs one to validate purchases. No analytics, no crash reporting, no remote fonts, no telemetry.

This is enforced mechanically: `verify.sh` greps for `URLSession`, `URLRequest`, `NWConnection`, and
`CFNetwork` outside RevenueCat, and fails the gate if any appear.

## Why this is a product decision, not a technical preference

It unlocks a truthful **"No Data Collected"** answer on Apple's App Privacy questionnaire.

That answer is worth more than it looks:

1. **It is the cleanest possible App Review signal.** A privacy app that transmits data invites
   scrutiny of every claim it makes. One that provably transmits nothing does not
2. **It is the marketing.** "Your documents never leave your phone" is only credible if it is
   literally true. The moment one analytics SDK is added, the claim becomes a lie and the product's
   central promise collapses
3. **It removes a whole class of obligations** — no privacy policy complexity around data handling,
   no DPA questions, no breach surface. There is nothing to breach

## Cost of the decision

- No usage analytics. We fly blind on in-app behaviour and rely on RevenueCat's purchase-side data
  for the only metrics that matter commercially
- No remote crash reporting. TestFlight crash reports via `asc crash triage` cover the beta period
- No remotely-tunable feature flags outside what RevenueCat's Offerings already provide

All acceptable. Losing the privacy claim would not be.

## Enforcement

- `CLAUDE.md` rule 1 — stated as non-negotiable for every agent
- `verify.sh` step 3 — mechanical grep, fails the gate
- Verifier agent — checks it explicitly once per phase

Three layers because this is the rule most likely to be broken innocently, by an agent adding a
"harmless" analytics call or a Google Fonts URL.

**Related:** [[DEC-001-app-concept]] · [[CLAUDE.md]]
