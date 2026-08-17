---
id: memory-index
date: 2026-08-17
phase: 2
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

**Phase 0, Phase 1 and Phase 2 complete.** The app now runs the whole loop: a document comes in by
camera, photo or PDF, detection marks what it found, the editor lets the user decide, and export
destroys it once and saves the result. `./verify.sh` last recorded exit 0 with **98 tests, 0
failures**. Phase 2's exit criterion from `plan.md` — *a document goes photo → redacted export, end
to end* — is met, and was **observed in the simulator**, not reasoned about: 3 taps to a live editor,
5 to a saved file, with the exported bytes pulled out of the app container and inspected pixel by
pixel.

Full write-ups in three depths:
Phase 1 — [[phase-1-technical]] · [[phase-1-non-technical]] · [[phase-1-guide-for-kids]]
Phase 2 — [[phase-2-technical]] · [[phase-2-non-technical]] · [[phase-2-guide-for-kids]]

| Feature | Status | Note |
|---|---|---|
| F02 design system | `built` | Awaiting an independent pass since Phase 1 |
| F03 PII detection engine | `built` | **`verified` was revoked in Phase 2** — projected boxes drifted; fixed, needs re-rating |
| F04 irreversible redaction core | `built` | Engine unchanged in Phase 2; still awaiting an independent pass |
| F05 SwiftData persistence | `built` | Exercised for real by Export and Library this phase |
| F06 scan / import | `in_progress` | Agent declined to claim `built` for uncompiled code; it now compiles and runs |
| F07 redaction editor | `built` | Draws on the geometry the fixer changed; needs re-rating |
| F08 export (PNG/PDF) | `built` | Annotation audit singled out by the verifier as correct |
| F09 library | `built` | Delete genuinely purges vault files before the record |
| F11 onboarding + sample | **`verified`** | Reviewer path observed: 3 taps, ~20s, no camera or account |

**Immediate next action:** an independent verifier pass over **F02, F03, F04, F05, F06, F07, F08,
F09** now that the gate is green — the fixer applied the findings and may not verify its own work
(`CLAUDE.md` rule 7). In parallel, the **human must publish the three legal pages**
([[legal-urls-not-published]]) — that one blocks submission and no code change can fix it. Then
Phase 3 — RevenueCat SDK and paywall (F10), plus Milestone 3.

| Milestone | State |
|---|---|
| M1 Registration | ✅ complete |
| M2 RevenueCat project | ✅ complete — project `51ce66cf`, Test Store wired, 2026-08-17 |
| M3 Test purchase | ⬜ next |
| M4 Store API call | ⬜ **unblocked** — Apple paperwork done |
| M5 Real purchase | ⬜ |

Apple monetization setup finished 2026-08-14 in a single day: Paid Apps Agreement Active, HDFC bank
account Active, W-8BEN Active. This was the one item that could have cost weeks. It didn't.
Remaining risks are App Review latency and the unpublished legal URLs.

**Done so far:** harness (`verify.sh`, `init.sh`, `feature_list.json`), memory vault + BM25 retrieval
index, governance docs, Xcode scaffold (F01), all of Phase 1's Core + DesignSystem modules, and all
of Phase 2's `Features/` tree plus the app-level wiring (`RootView`, `RouteDestination`,
`AppEnvironment`) — 98 passing tests.

**Next:** verifier pass over everything except F11, the human legal-pages task, then Phase 3
(RevenueCat paywall + entitlements, F10).

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

As built through Phase 2:

```
Core/Detection/    Models · Checksums · PatternDetector · NameDetector · LabelledFieldDetector
                   PIIClassifier · TextRecogniser
Core/Redaction/    RedactionStyle · RedactionEngine · MetadataStripper
Core/Persistence/  PersistenceModels · DocumentStore · FileVault · UsageTracker
DesignSystem/      Tokens · Typography · Motion · Surfaces · AmbientBackground · TokenGallery · Components/
Features/Shared/   RedactionSession · AppRoute+AppCoordinator · DocumentPipeline · RedactionRegion (ext only)
Features/Scan/     ImportPipeline · DocumentCameraView · ScanView
Features/Editor/   EditorGeometry · ScanlineAnimation · DetectionOverlay · ManualRegionLayer
                   DetectionListSheet · EditorView · EditorMetrics
Features/Export/   AnnotationAudit · InsecureMarkupSheet · ExportPipeline · ExportView
Features/Library/  LibraryView · DocumentDetailView · LibraryModel · ThumbnailLoader · …
Features/Onboarding/ SampleDocument · OnboardingView · AboutView · OnboardingState
App/               RedactApp · RootView · RouteDestination · AppEnvironment · LegalLinks
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

## Key learnings — Phase 2

1. **OCR is a blind oracle for the leak that matters most.** Vision discards a lone glyph stranded
   against a black bar, so an export that visibly renders `Date of Birth: 1` reads back as
   `Date of Birth:`. Every text-level assertion in the suite was blind to a one-character leak — and
   a leading digit narrows a guess enormously. The oracle had to become **pixels**: Vision's own
   per-character measurement of the source as ground truth, asserting the export is one flat colour
   across that footprint. This generalises: any test that judges redaction by OCR alone can miss a
   one-character leak, so other documents need pixel-level spot checks.
2. **A test that passes on the broken build is worse than no test.** The fixer's first end-to-end
   test passed against the defect and was nearly shipped as proof. Reverting the fix and confirming
   the failure is the step that made it evidence.
3. **Compiling is not running; running is not looking.** Four sessions stopped at the compile line.
   The gate was green, 86 tests passed, and the sample was still leaking three secrets. It was found
   by pulling the artifact out of the app container and looking at the pixels.
4. **Don't trust the attribution — drive the pipeline first.** The verifier's single reported cause
   explained only half the leak. The name was never detected at all (`NLTagger` returns nothing for
   `Employee Ananya Mehra` — a prose model with no sentence), *and* the geometry drifted. One
   symptom, two defects.
5. **A printed label is evidence, in every language.** `LabelledFieldDetector` beats a prose-trained
   NER model on forms, which is what most documents worth redacting are. Label set kept narrow —
   bars over job titles teach users to switch bars off.
6. **Ask the framework to measure; never interpolate.** Splitting a line box by character count
   fails on proportional type. But `VNRecognizedText.boundingBox(for:)` also returns a page-sized
   quad for a lone space, so every framework answer needs a plausibility gate.
7. **Fail closed by construction.** `disabledDetections` stores opt-*outs*, so a detection arriving
   later is redacted by default. An opt-in set would fail open, and failing open here ships live PII.
8. **Make the dangerous thing inexpressible.** No feature file contains a `1 - y`; the only route
   from a detection to a drawable box is `RedactionRegion(detected:)`. Even `AnnotationAudit`'s
   PDF-space conversion delegates to Core's single flip.
9. **Edits are decisions, not pixels.** Undo is a struct swap, the preview cannot drift from the
   export, and there is exactly one destroy path to prove correct.
10. **Geometric staggering beats scheduled staggering.** One animated `Double` plus a per-box
    threshold gives the scanline reveal for free, in reading order, and stays correct when the
    layout changes mid-sweep.
11. **A warning that cries wolf is worse than none.** The annotation audit only fires when there is
    *extractable text under the mark* — otherwise every signed contract triggers it and users learn
    to tap through the one that mattered.
12. **`grep` gates are not comment-aware.** Doc comments explaining why the app makes no network
    calls tripped `verify.sh`'s network check. Both were reworded.

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
| [[gotcha-xcode-select]] — Simulator MCP blocked; `simctl` workaround in use | open, `simctl` proved sufficient for Phase 2's verification |
| [[legal-urls-not-published]] — privacy / terms / support all 404 | **open, escalated to human. Blocks submission**: App Store Connect validates the privacy URL as metadata before review |
| [[nltagger-misses-names-on-forms]] — "August" in the sample title is tagged `personName` | open, over-redaction only, needs a `detect-engine` decision |
| [[vision-per-character-geometry]] — per-character boxes; whitespace and out-of-line answers must be discarded | resolved in code, documented |
| [[manual-region-resize-undo]] — resizing a manual box costs two undo steps | open, four-line fix on `RedactionSession` |
| [[library-pro-access-seam]] — `\.libraryProAccess` defaults to false and nothing sets it | open until Phase 3 |
| [[library-layout-constants-not-tokens]] — five constants live in the feature, not `Token` | open, cosmetic |

Also unfinished from Phase 1: display fonts not bundled (system fallback), contrast unmeasured
(`Token.Text.faint` on `Token.BG.base` is the suspected 4.5:1 failure), and reduce-motion checkable
only in the simulator.

## Phase documentation

| Phase | Technical | Non-technical | For kids |
|---|---|---|---|
| 1 | [[phase-1-technical]] | [[phase-1-non-technical]] | [[phase-1-guide-for-kids]] |
| 2 | [[phase-2-technical]] | [[phase-2-non-technical]] | [[phase-2-guide-for-kids]] |

## Session log

| Date | Log | Summary |
|---|---|---|
| 2026-08-17 | [[2026-08-17-01]] | Phase 0 — harness, memory layer, governance docs; Phase 1 — design system, detection, redaction, persistence; Phase 2 — shared contract, scan, editor, export, library, onboarding; verify + fix; sample-document leak found in the exported pixels and fixed; gate green at 98 tests |
