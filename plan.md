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
| 3 | First test purchase | ⬜ | Test Store key — no Apple setup needed |
| 4 | First Store API call | ⬜ | **Unblocked.** Needs app record + IAP products + `.p8` |
| 5 | First real purchase | ⬜ | App live; buy it yourself |

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
| **3** | RevenueCat SDK + paywall | Test Store purchase flips the entitlement; **M3** | ◀ next |
| **4** | App Store Connect record, IAP products, real key | RevenueCat shows a Store API call; **M4** | ⬜ |
| **5** | Polish, accessibility, final audit, TestFlight, submit | `asc validate` zero blockers; submitted by 09-05 | ⬜ |
| **6** | Live | Own purchase completes; **M5**; Devpost writeup + demo video | ⬜ |

### Every phase closes the same way — no exceptions

1. Builders finish → `verify.sh` green
2. **One** verifier pass (independent, fresh context, read-only)
3. **One** fixer pass; anything unresolved → `gotchas/` + escalate to human
4. Update `docs/memory.md` and the session log
5. Generate the three-doc triad: `technical.md`, `non-technical.md`, `guide-for-kids.md`
6. Rebuild the memory index

A phase is not done until a fresh session could resume it cold from the docs alone.

## Current status — Phase 2 complete

**Done**
- Phase 0: repo, `.gitignore`, `CLAUDE.md` / `AGENTS.md` / `agent.md`, `feature_list.json`,
  `verify.sh` + `init.sh`, memory vault + BM25 index, DEC-001…DEC-005
- Phase 1: design system (F02), detection engine (F03), irreversible redaction core (F04),
  SwiftData persistence (F05) — see [[phase-1-technical]]
- Phase 2: the shared contract (`Features/Shared/**`), scan/import (F06), editor (F07),
  export (F08), library (F09), onboarding + bundled sample (F11), and the app-level wiring
  (`RootView`, `RouteDestination`, `AppEnvironment`) — see [[phase-2-technical]]
- Phase 1's escalated PDF pass-through question answered: **detect and offer**, shipped as
  `AnnotationAudit` + `InsecureMarkupSheet`
- Gate: `./verify.sh` exit 0, **98 tests, 0 failures**; app installs, launches and completes the
  full loop on the iOS 26.5 simulator

**Verified vs claimed**
- Only **F11** carries `verified`. **F03 lost its `verified` status this phase** — the exported
  sample was leaking the leading character of two identifiers and the employee's name entirely.
  Both defects are fixed and covered by a pixel-level test; the fixer may not re-rate its own work.

**Next**
1. **Human, blocking:** publish the three GitHub Pages behind `RedactApp/App/LegalLinks.swift` and
   confirm a 200. App Store Connect validates the privacy URL as metadata before review; a 404 burns
   a cycle. [[legal-urls-not-published]]
2. Independent verifier pass over F02–F09 now that the gate is green
3. `detect-engine` decides on the "August" month-name false positive
   ([[nltagger-misses-names-on-forms]])
4. Phase 3 — RevenueCat SDK, paywall, entitlements (F10) and **Milestone 3** (first test purchase)

## Risks

| Risk | Mitigation |
|---|---|
| App Review rejection cycles | Submit by 09-05; TestFlight first for a lighter early review; checklist enforced from day one |
| Scope creep | `feature_list.json` is fixed at 16 features. Additions require dropping something |
| Redaction not actually irreversible | Hard test requirement (F04) **plus** a pixel-level oracle (`SampleDocumentLeakTests`) after Phase 2 proved OCR-only tests are blind to a one-character leak |
| Unpublished legal URLs fail ASC metadata validation | Human task, tracked as the #1 next action. Must return 200 before the first submission attempt |
| Agent drift / lost context | Memory layer + scope allowlists + bounded loop ([[DEC-005-bounded-loop]]) |
| Design ambition vs deadline | The signature animation is the only expensive UI item; everything else uses tokens |
