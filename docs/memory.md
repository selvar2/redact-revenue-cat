---
id: memory-index
date: 2026-08-17
phase: 1
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

**Phase 0 complete. Phase 1 complete** — design system, detection engine, redaction core and
persistence are built, integrated, verified once and fixed once. `./verify.sh` last recorded exit 0
with **79 tests, 0 failures**. Phase 1's exit criteria from `plan.md` — *irreversibility test
passes, token gallery renders* — are met.

Full write-up in three depths: [[phase-1-technical]] · [[phase-1-non-technical]] ·
[[phase-1-guide-for-kids]].

| Feature | Status | Note |
|---|---|---|
| F02 design system | `built` | RootView typography/magic-number findings fixed; needs re-verification |
| F03 PII detection engine | **`verified`** | Checksums confirmed against published algorithms |
| F04 irreversible redaction core | `built` | Engine passes on substance; metadata assertions fixed, awaiting independent pass |
| F05 SwiftData persistence | `built` | 9 tests added by the fixer; not independently verified |

**Immediate next action:** an independent verifier pass over **F02, F04, F05** now that the gate is
green. The fixer applied the findings and may not verify its own work (`CLAUDE.md` rule 7).
Then Phase 2 — Scan → Editor → Export (F06–F09, F11).

| Milestone | State |
|---|---|
| M1 Registration | ✅ complete |
| M2 RevenueCat project | ✅ complete — project `51ce66cf`, Test Store wired, 2026-08-17 |
| M3 Test purchase | ⬜ |
| M4 Store API call | ⬜ **unblocked** — Apple paperwork done |
| M5 Real purchase | ⬜ |

Apple monetization setup finished 2026-08-14 in a single day: Paid Apps Agreement Active, HDFC bank
account Active, W-8BEN Active. This was the one item that could have cost weeks. It didn't.
Remaining risk is App Review latency alone.

**Done so far:** harness (`verify.sh`, `init.sh`, `feature_list.json`), memory vault + BM25 retrieval
index, governance docs (`CLAUDE.md`, `AGENTS.md`, `agent.md`), Xcode scaffold (F01), and all of
Phase 1's Core + DesignSystem modules with 79 passing tests.

**Next:** verifier pass over F02/F04/F05, then Phase 2 — the Scan → Editor → Export loop, plus
Milestone 2 (RevenueCat project, human, 15 min).

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

As built in Phase 1 (`Features/` is still empty — that is Phase 2):

```
Core/Detection/    Models · Checksums · PatternDetector · NameDetector · PIIClassifier · TextRecogniser
Core/Redaction/    RedactionStyle · RedactionEngine · MetadataStripper
Core/Persistence/  PersistenceModels · DocumentStore · FileVault · UsageTracker
DesignSystem/      Tokens · Typography · Motion · Surfaces · AmbientBackground · TokenGallery · Components/
```

Pipeline: `Data → TextRecogniser (Vision) → PIIClassifier (patterns + NER) → [DetectedPII] →
RedactionRegion → RedactionEngine → Data`. Only `Data` and `Sendable` values cross module
boundaries, which is how the whole path satisfies Swift 6 complete strict concurrency with zero
`@unchecked Sendable`.

## Key learnings — Phase 1

1. **Build the attack before the defence.** `IrreversibilityTests` ships two deliberately broken
   controls (a translucent overlay, a `PDFAnnotation` square) that must *leak*. Without them, an
   attack harness that went blind would report a clean pass for a totally broken engine. Same
   reasoning caught a **vacuous** metadata test: `kCGPDFContextTitle` set via `beginPage(pageInfo:)`
   is *page* info, so the test was asserting removal on a document that never had a Title.
2. **Assert on what leaks, not on what the SDK emits.** ImageIO synthesises `{Exif}` and `{TIFF}`
   on every write, so a container-name assertion can never pass. The fix belonged in the assertion
   (`identifyingMetadataKeys(in:)`, key-level), not in the stripper. [[imageio-synthesises-exif-tiff]]
3. **Rebuild, never edit.** Both the pixel path and the PDF path construct a new file rather than
   deleting fields from the old one. Deny-lists rot the moment an SDK adds a dictionary.
4. **Checksums beat regex shape.** A bare `\d{12}` flags invoice totals; a false-positive-heavy
   review screen trains users to accept everything, which is how real PII gets missed.
5. **Encode unenforceable rules as API.** Rule 3 (no hardcoded values) and rule 4 (reduceMotion)
   cannot be enforced by review across parallel agents, so `.typeStyle(_:)` and
   `\.accessibleAnimation` make the accessible, tokenised path the *shortest* path to write.
6. **Coordinate-space flips belong in exactly three functions.** Vision is bottom-left origin;
   UIKit/CG/SwiftUI are top-left. Hand-rolling the flip at call sites is the defining bug of this
   app class, and here it is a correctness failure, not a cosmetic one.
7. **An honest documented gap beats an invented API.** `FoundationModelClassifier` delegates to the
   heuristic path rather than guessing at an unconfirmed framework surface that would have broken
   every other agent's build. [[gotcha-foundation-models-api-unconfirmed]]
8. **Generated project file, disjoint allowlists.** Four parallel builders produced exactly one
   mechanical collision (two `Models.swift` in one target) and zero `.pbxproj` conflicts.

## Monetization

Entitlement `pro`. Free: 3 documents/month, PNG, single page. Pro: unlimited, multi-page PDF, batch,
custom rules, audit log. Targeting the **HAMM award** via depth — remote paywalls, an A/B experiment,
Customer Center, win-back offers — not just a `purchase()` call.

## Traps already known

| Trap | Status |
|---|---|
| [[pdf-passthrough-pages-keep-annotations]] — region-free PDF pages are inserted verbatim and keep annotations another tool may have drawn, so an inherited peel-off black box ships intact | **open, escalated to human.** Needs a product decision (flatten / strip / warn) at Phase 2 F09 export. Recommended: detect at export, offer flattening as an explicit choice |
| [[gotcha-foundation-models-api-unconfirmed]] — `FoundationModelClassifier` performs no LLM reasoning, delegates 100% to `HeuristicClassifier` | open, documented in code, `feature_list.json`, and the gotcha |
| [[imageio-synthesises-exif-tiff]] — ImageIO always writes `{Exif}`/`{TIFF}` containers | **resolved** — assertions moved to key level |
| [[gotcha-xcode-select]] — Simulator MCP blocked; `simctl` workaround in use | open, needs a human `sudo xcode-select -s …` before Phase 2 |

Also unfinished from Phase 1: display fonts not bundled (system fallback), contrast unmeasured
(`Token.Text.faint` on `Token.BG.base` is the suspected 4.5:1 failure), and reduce-motion checkable
only in the simulator.

## Phase documentation

| Phase | Technical | Non-technical | For kids |
|---|---|---|---|
| 1 | [[phase-1-technical]] | [[phase-1-non-technical]] | [[phase-1-guide-for-kids]] |

## Session log

| Date | Log | Summary |
|---|---|---|
| 2026-08-17 | [[2026-08-17-01]] | Phase 0 — harness, memory layer, governance docs; Phase 1 — design system, detection, redaction, persistence, verify + fix, gate green |
