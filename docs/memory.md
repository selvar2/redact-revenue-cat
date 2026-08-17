---
id: memory-index
date: 2026-08-17
phase: 0
tags: [index, state]
status: living
---

# Project Memory — Redact

> **Any agent or human starting a session reads this file second, right after `CLAUDE.md`.**
> It is the answer to "where are we and why is it like this?"
>
> Search deeper history: `python3 tools/memory_index.py query "<topic>"`

## What we are building

**Redact** — an iOS app that finds personal information in documents and photos and removes it
**irreversibly**, entirely on-device. No server, no network, no data collection.

Built solo for **RevenueCat Shipaton 2026**. App Store submission target **2026-09-05**;
the hackathon closes **2026-09-30**.

The differentiator is correctness: most "redaction" tools draw a black box over text that is still
recoverable underneath. Ours destroys the underlying data and proves it with a test.

## Current state — 2026-08-17

**Phase 0, in progress.**

| Milestone | State |
|---|---|
| M1 Registration | ✅ complete |
| M2 RevenueCat project | ⬜ next |
| M3 Test purchase | ⬜ |
| M4 Store API call | ⬜ **unblocked** — Apple paperwork done |
| M5 Real purchase | ⬜ |

Apple monetization setup finished 2026-08-14 in a single day: Paid Apps Agreement Active, HDFC bank
account Active, W-8BEN Active. This was the one item that could have cost weeks. It didn't.
Remaining risk is App Review latency alone.

**Done so far:** harness (`verify.sh`, `init.sh`, `feature_list.json`), memory vault + BM25 retrieval
index, governance docs (`CLAUDE.md`, `AGENTS.md`, `agent.md`).

**Next:** Xcode project scaffold (F01), then Workflow 1 — design system, detection engine,
redaction core.

## Key decisions

| ID | Decision | Why in one line |
|---|---|---|
| [[DEC-001-app-concept]] | Build Redact, not a tracker or AI chat wrapper | Survives Guideline 4.2/4.3, no UGC burden, zero API cost |
| [[DEC-002-design-language]] | Port the violet→amber dark glass language from the user's HTML | Cohesive with existing work; targets the Design Award |
| [[DEC-003-ios-target]] | iOS 17 floor, iOS 26 `FoundationModels` as gated enhancement | Real on-device LLM story without abandoning the install base |
| [[DEC-004-no-network]] | Zero network calls except the RevenueCat SDK | Enables a truthful "No Data Collected" App Privacy answer |
| [[DEC-005-bounded-loop]] | One verifier pass + one fixer pass per phase, 7 total | Unbounded verify→fix cycles burn budget without converging |

## Architecture at a glance

```
RedactApp/
├─ App/            entry, RevenueCat configure, routing
├─ DesignSystem/   tokens, glass surfaces, typography, motion
├─ Features/       Scan · Editor · Export · Library · Paywall · Onboarding
└─ Core/           Detection · Redaction · Entitlements · Persistence
```

Detection = Vision OCR (with bounding boxes) + `NLTagger` NER + a regex layer for Indian IDs
(PAN, Aadhaar, IFSC, GSTIN), plus `FoundationModels` classification on iOS 26 only.

## Monetization

Entitlement `pro`. Free: 3 documents/month, PNG, single page. Pro: unlimited, multi-page PDF, batch,
custom rules, audit log. Targeting the **HAMM award** via depth — remote paywalls, an A/B experiment,
Customer Center, win-back offers — not just a `purchase()` call.

## Traps already known

None logged yet. They go in `docs/memory/gotchas/` as they are hit — see [[gotchas]].

## Session log

| Date | Log | Summary |
|---|---|---|
| 2026-08-17 | [[2026-08-17-01]] | Phase 0 — harness, memory layer, governance docs |
