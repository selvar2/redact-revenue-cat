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
| 2 | RevenueCat project created | ⬜ | Human, 15 min |
| 3 | First test purchase | ⬜ | Test Store key — no Apple setup needed |
| 4 | First Store API call | ⬜ | **Unblocked.** Needs app record + IAP products + `.p8` |
| 5 | First real purchase | ⬜ | App live; buy it yourself |

Apple's financial paperwork — the one item that could have cost weeks — was completed on 2026-08-14.
The only remaining external risk is App Review latency.

## Awards being targeted

Not the Grand Prize; that goes to teams with existing distribution. Three are winnable solo:

- **RevenueCat Design Award** — pure craft, needs no audience. See [[DEC-002-design-language]]
- **HAMM (Help Apps Make Money)** — depth of RevenueCat usage: remote paywalls, an A/B experiment,
  Customer Center, win-back offers. A technical criterion, where thoroughness beats reach
- **#BuildInPublic** — the journey. Start posting now; retroactive threads read as manufactured.
  The India/Stripe/App-Store-paperwork story is genuinely differentiated

## Phases

| # | Output | Exit criteria |
|---|---|---|
| **0** | Harness, memory vault, governance docs, Xcode scaffold, RevenueCat project | `verify.sh` green; app launches in simulator; **M2** |
| **1** | Design system, detection engine, redaction core | Irreversibility test passes; token gallery renders |
| **2** | Scan → Editor → Export loop | A document goes photo → redacted export, end to end |
| **3** | RevenueCat SDK + paywall | Test Store purchase flips the entitlement; **M3** |
| **4** | App Store Connect record, IAP products, real key | RevenueCat shows a Store API call; **M4** |
| **5** | Polish, accessibility, final audit, TestFlight, submit | `asc validate` zero blockers; submitted by 09-05 |
| **6** | Live | Own purchase completes; **M5**; Devpost writeup + demo video |

### Every phase closes the same way — no exceptions

1. Builders finish → `verify.sh` green
2. **One** verifier pass (independent, fresh context, read-only)
3. **One** fixer pass; anything unresolved → `gotchas/` + escalate to human
4. Update `docs/memory.md` and the session log
5. Generate the three-doc triad: `technical.md`, `non-technical.md`, `guide-for-kids.md`
6. Rebuild the memory index

A phase is not done until a fresh session could resume it cold from the docs alone.

## Current status — Phase 0

**Done**
- Repo initialized; `.gitignore` with secrets blocked first
- `CLAUDE.md` (ten rules), `AGENTS.md` (roster + allowlists), `agent.md` (system prompt)
- `feature_list.json` — F00–F15 with acceptance criteria
- `verify.sh` (7-check gate) and `init.sh` (bootstrap) — both run clean
- Memory vault + BM25 retrieval index — 37 chunks across 7 notes, queries answering
- Decisions DEC-001 … DEC-005

**Next**
- F01 Xcode project scaffold
- Milestone 2: RevenueCat project (human, 15 min)
- Workflow 1: design system · detection engine · redaction core · persistence

## Risks

| Risk | Mitigation |
|---|---|
| App Review rejection cycles | Submit by 09-05; TestFlight first for a lighter early review; checklist enforced from day one |
| Scope creep | `feature_list.json` is fixed at 16 features. Additions require dropping something |
| Redaction not actually irreversible | Hard test requirement (F04). Not shippable without it |
| Agent drift / lost context | Memory layer + scope allowlists + bounded loop ([[DEC-005-bounded-loop]]) |
| Design ambition vs deadline | The signature animation is the only expensive UI item; everything else uses tokens |
