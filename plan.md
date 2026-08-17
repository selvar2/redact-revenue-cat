# plan.md — Redact Build Plan & Milestone Tracker

> Living document. Updated at the close of every phase.
> Current state lives in `docs/memory.md`; machine state in `feature_list.json`.

## The goal

Ship **Redact** — an on-device PII scrubber for iOS — live on the App Store, monetized with
RevenueCat, before the Shipaton 2026 deadline.

- **App Store submission target:** 2026-09-05
- **Shipaton closes:** 2026-09-30, 11:45 PM PT
- Buffer is deliberate: it absorbs 2–3 App Review rejection cycles at 24–48h each.

## Shipaton milestones

| # | Milestone | State | Gate |
|---|---|---|---|
| 1 | Registration complete | ✅ | — |
| 2 | RevenueCat project created | ✅ | Project created, Test Store wired, 2026-08-17 |
| 3 | First test purchase | ✅ | Test Store purchase completed in the simulator, 2026-08-17 |
| 4 | First Store API call | ✅ | Real `appl_` key live; StoreKit verified in device log, 2026-08-17 |
| 5 | First real purchase | ⬜ | Blocked on IAP products, then app live; buy it yourself |

Apple's financial paperwork — the one item that could have cost weeks — was completed on 2026-08-14.
The remaining external risks are App Review latency and the three unpublished legal URLs
([[legal-urls-not-published]]).

## Awards being targeted

Not the Grand Prize; that goes to teams with existing distribution. Three are winnable solo:

- **RevenueCat Design Award** — pure craft, needs no audience. See [[DEC-002-design-language]]
- **HAMM (Help Apps Make Money)** — depth of RevenueCat usage: remote paywalls, an A/B experiment,
  Customer Center, win-back offers. A technical criterion, where thoroughness beats reach
- **#BuildInPublic** — the journey. Start posting now; retroactive threads read as manufactured.
  The India/Stripe/App-Store-paperwork story is genuinely differentiated

## Phases

| # | Output | Exit criteria | State |
|---|---|---|---|
| **0** | Harness, memory vault, governance docs, Xcode scaffold, RevenueCat project | `verify.sh` green; app launches in simulator; **M2** | ✅ complete |
| **1** | Design system, detection engine, redaction core | Irreversibility test passes; token gallery renders | ✅ complete |
| **2** | Scan → Editor → Export loop | A document goes photo → redacted export, end to end | ✅ complete — observed in the simulator, artifact inspected at pixel level |
| **3** | RevenueCat SDK + paywall | Test Store purchase flips the entitlement; **M3** | ✅ complete — purchase observed in the simulator, entitlement flipped, Export switched to Pro copy |
| **4** | App Store Connect record, IAP products, real key | RevenueCat shows a Store API call; **M4** | ◀ next |
| **5** | Polish, accessibility, final audit, TestFlight, submit | `asc validate` zero blockers; submitted by 09-05 | ◀ in progress — build v1.0(2) **VALID** on App Store Connect |
| **6** | Live | Own purchase completes; **M5**; Devpost writeup + demo video | ⬜ |

### Every phase closes the same way — no exceptions

1. Builders finish → `verify.sh` green
2. **One** verifier pass (independent, fresh context, read-only)
3. **One** fixer pass; anything unresolved → `gotchas/` + escalate to human
4. Update `docs/memory.md` and the session log
5. Generate the three-doc triad: `technical.md`, `non-technical.md`, `guide-for-kids.md`
6. Rebuild the memory index

A phase is not done until a fresh session could resume it cold from the docs alone.

## Current status — Phase 3 complete

**Done**
- Phase 0: repo, `.gitignore`, `CLAUDE.md` / `AGENTS.md` / `agent.md`, `feature_list.json`,
  `verify.sh` + `init.sh`, memory vault + BM25 index, DEC-001…DEC-006
- Phase 1: design system (F02), detection engine (F03), irreversible redaction core (F04),
  SwiftData persistence (F05) — see [[phase-1-technical]]
- Phase 2: shared contract, scan/import (F06), editor (F07), export (F08), library (F09),
  onboarding + bundled sample (F11), app-level wiring — see [[phase-2-technical]]
- Phase 3 (F10): `Core/Entitlements/**` — SDK configuration, the one entitlement state machine, the
  gateway seam and `DocumentAllowance`; `Features/Paywall/**` — the paywall on a remote path with a
  native fallback, runtime-derived pricing, the compiled-in compliance footer, contextual placements
  and the A/B seam; plus real Pro gating in Scan, Export and Library — see [[phase-3-technical]]
- Gate: `./verify.sh` exit 0 (build succeeded, tests passed, index rebuilt); **M3 observed** —
  test purchase completed, sheet dismissed itself, Export switched to Pro copy

**Verified vs claimed**
- Only **F11** carries `verified`. **F10 is `built`** — the fixer applied nine fixes across the
  verifier's seven findings (four critical/high) and may not rate its own work (`CLAUDE.md` rule 7).
- Not yet done and honestly outstanding: the App Review checklist has not been walked line by line;
  Restore Purchases has not been exercised on a real device with a real purchase; the legal links
  cannot be exercised at all until they resolve.

**Next**
1. **Human, blocking:** publish the three GitHub Pages behind `RedactApp/App/LegalLinks.swift`
   (`https://selvar2.github.io/redact-revenue-cat/{privacy,terms,support}.html`) and confirm
   `curl -sI` returns 200 on each. Terms and Privacy are now live, tappable links **on the paywall**,
   so a 404 is both an ASC metadata-validation failure and a reviewer-facing rejection.
   [[legal-urls-not-published]]
2. Independent verifier pass over F02–F10 now that the gate is green
3. Decide where `ManageSubscriptionView` (Customer Center) belongs — About, or Library. Built and
   correct, currently unreferenced; it is part of the HAMM case
4. `PaywallStore` has no tests of its own (the 11 `EntitlementStore` tests cover the state machine it
   drives) — add a fake-backed test target if budget allows
5. Phase 4 — App Store Connect record, the three IAP products, swap `test_` for `appl_`, **M4**

## Risks

| Risk | Mitigation |
|---|---|
| App Review rejection cycles | Submit by 09-05; TestFlight first for a lighter early review; checklist enforced from day one |
| Scope creep | `feature_list.json` is fixed at 16 features. Additions require dropping something |
| Redaction not actually irreversible | Hard test requirement (F04) **plus** a pixel-level oracle (`SampleDocumentLeakTests`) after Phase 2 proved OCR-only tests are blind to a one-character leak |
| Unpublished legal URLs fail ASC metadata validation **and are now tappable on the paywall** | Human task, the #1 next action. Must return 200 before the first submission attempt |
| Agent drift / lost context | Memory layer + scope allowlists + bounded loop ([[DEC-005-bounded-loop]]) |
| Design ambition vs deadline | The signature animation is the only expensive UI item; everything else uses tokens |
