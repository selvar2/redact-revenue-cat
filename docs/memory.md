---
id: memory-index
date: 2026-08-17
phase: 4
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

**Phases 0–3 complete.** The app runs the whole loop (camera/photo/PDF → detection → editor →
irreversible export → library) **and can now sell a subscription**: one entitlement state machine in
`Core/Entitlements`, a real paywall on two rendering paths, and every Pro feature gated on the `pro`
entitlement rather than a constant. `./verify.sh` last recorded **exit 0** — build succeeded, tests
passed, memory index rebuilt (115 `func test` across `Tests/**`, 11 of them new
`EntitlementStoreTests`).

Phase 3's exit criterion from `plan.md` — *a Test Store purchase flips the entitlement; M3* — is met
and was **observed in the simulator**: sample → *Review and export* → *See what Pro includes* showed
Yearly $29.99 (Save 50%, ≈$2.50/mo) and Monthly $4.99 with Restore Purchases, the auto-renewal
sentence and both legal links; *Test valid purchase* completed, the sheet dismissed itself, and the
Export screen switched to Pro copy.

Full write-ups in three depths:
Phase 1 — [[phase-1-technical]] · [[phase-1-non-technical]] · [[phase-1-guide-for-kids]]
Phase 2 — [[phase-2-technical]] · [[phase-2-non-technical]] · [[phase-2-guide-for-kids]]
Phase 3 — [[phase-3-technical]] · [[phase-3-non-technical]] · [[phase-3-guide-for-kids]]
Phase 4 — [[phase-4-technical]] · [[phase-4-non-technical]] · [[phase-4-guide-for-kids]]

| Feature | Status | Note |
|---|---|---|
| F02 design system | `built` | Awaiting an independent pass since Phase 1 |
| F03 PII detection engine | `built` | **`verified` was revoked in Phase 2** — geometry fixed, needs re-rating |
| F04 irreversible redaction core | `built` | Engine unchanged since Phase 1; awaiting an independent pass |
| F05 SwiftData persistence | `built` | Exercised for real by Export and Library |
| F06 scan / import | `in_progress` | Now compiles, runs, and gates on the real entitlement |
| F07 redaction editor | `built` | Needs re-rating after the Phase 2 geometry fix |
| F08 export (PNG/PDF) | `built` | PDF is now genuinely Pro-gated via `ProAccess.exportTier` |
| F09 library | `built` | Audit log gated; delete still purges vault files before the record |
| **F10 paywall + entitlements** | **`built`** | Phase 3. Fixer applied all blockers and **may not** rate its own work — verifier must re-check |
| F11 onboarding + sample | **`verified`** | Reviewer path: 3 taps, ~20s, no camera or account |

**Immediate next actions:**
1. **Create the two subscription products in App Store Connect.** Group "Redact Pro" (`22315273`)
   exists but is **empty** — no sandbox or real purchase can succeed until `redact_pro_monthly` and
   `redact_pro_annual` exist there and are imported into RevenueCat. This is the single blocker
   between here and M5.
2. Independent verifier pass over **F02–F10** — the Phase 3 fixer applied nine fixes and cannot
   verify itself (`CLAUDE.md` rule 7).
3. **Human:** rotate `AuthKey_CDCMHRBW3C` — Admin-scoped, pasted into a chat transcript, and needed
   for Phase 5 TestFlight uploads anyway. Regenerate as **App Manager** ([[DEC-007-apple-key-types]]).
4. Design the **remote paywall** in RevenueCat's editor — the native fallback renders today; the
   remote one is the HAMM-award capability.
5. Phase 5 — TestFlight, then App Store submission by **2026-09-05**.

| Milestone | State |
|---|---|
| M1 Registration | ✅ complete |
| M2 RevenueCat project | ✅ complete — project created, Test Store wired, 2026-08-17 |
| M3 Test purchase | ✅ **complete — observed end to end in the simulator, 2026-08-17** |
| M4 Store API call | ✅ **complete — real `appl_` key live, StoreKit verified in device log, 2026-08-17** |
| M5 Real purchase | ⬜ next — needs IAP products, then app live on the App Store |

Apple monetization setup finished 2026-08-14 in a single day: Paid Apps Agreement Active, bank
account Active, W-8BEN Active. Legal URLs are now **published and returning 200**. Remaining risk is App Review latency alone.

**Done so far:** harness (`verify.sh`, `init.sh`, `feature_list.json`), memory vault + BM25 retrieval
index, governance docs, Xcode scaffold (F01), all of Phase 1's Core + DesignSystem modules, all of
Phase 2's `Features/` tree plus app-level wiring, and Phase 3's `Core/Entitlements/**` +
`Features/Paywall/**` + the gating in Scan / Export / Library.

## Apple / RevenueCat identifiers (live)

Everything a cold session needs; none of it secret. Secrets live in the keychain and `~/Downloads`,
never here — see [[DEC-007-apple-key-types]].

```
Apple ID (Account Holder)   SCRIPTKIDAPPLE7@GMAIL.COM   (SENTHILNATHAN RAJA)
Team ID                     8837BPRM4M
Bundle ID                   com.senthilnathanraja.redact
App Store Connect App ID    6802355309   "Redact: Hide Personal Info"   SKU REDACT-IOS-2026
Subscription group          "Redact Pro"  22315273        ← EMPTY, products not yet created
In-App Purchase Key ID      BU27GRYDV3
Issuer ID                   34fe7ae7-f498-44e2-82ae-a34c1e95e7d7
RevenueCat project          51ce66cf
RevenueCat App Store app    app8a75e71942  "Redact (App Store)"
Public SDK key (safe)       appl_DuknWVjObDvejcuDZURluQLtfDS
Entitlement / Offering      pro / default  ($rc_monthly, $rc_annual)
Product identifiers         redact_pro_monthly, redact_pro_annual
GitHub                      github.com/selvar2/redact-revenue-cat  (public)
Legal pages (200 OK)        selvar2.github.io/redact-revenue-cat/{privacy,terms,support}.html
```

⚠️ **Five other Admins** hold All-Apps access to the developer account. Each can see this app,
upload builds, change pricing and read financial reports. Flagged to the human 2026-08-17; removing
access is not an agent's decision.

## Key decisions

| ID | Decision | Why in one line |
|---|---|---|
| [[DEC-001-app-concept]] | Build Redact, not a tracker or AI chat wrapper | Survives Guideline 4.2/4.3, no UGC burden, zero API cost |
| [[DEC-002-design-language]] | Port the violet→amber dark glass language from the user's HTML | Cohesive with existing work; targets the Design Award |
| [[DEC-003-ios-target]] | iOS 17 floor, iOS 26 `FoundationModels` as gated enhancement | Real on-device LLM story without abandoning the install base |
| [[DEC-004-no-network]] | Zero network calls except the RevenueCat SDK | Enables a truthful "No Data Collected" App Privacy answer |
| [[DEC-005-bounded-loop]] | One verifier pass + one fixer pass per phase, 7 total | Unbounded verify→fix cycles burn budget without converging |
| [[DEC-006-support-email-deferred]] | Publish the personal support address now, alias later | Apple requires a reachable contact; inbox hygiene is not critical-path |
| [[DEC-007-apple-key-types]] | Generate a new In-App Purchase key rather than reuse the ASC API key | Wrong key type fails **silently** — customers pay and get nothing |

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
Core/Entitlements/  RevenueCatConfig · EntitlementGateway · EntitlementStore · DocumentAllowance
Features/Paywall/   PaywallView(RedactPaywallView) · NativePaywallView · PaywallStore · PaywallContext
                    PaywallExperiment · PaywallPricing · PaywallPlanRow · PaywallLegalFooter
                    CustomerCenterView (built, unreferenced)
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

## Key learnings — Phase 3

1. **Two state machines is the default failure of a parallel monetization build.** `EntitlementStore`
   and `PaywallStore` were written concurrently and both subscribed to `customerInfoStream`, both
   called `purchase()`, both kept an `isPro`. They agreed on day one and would have diverged
   silently. The rule that survives: *the screen owns screen state; entitlement truth lives in
   exactly one type in `Core`.* [[two-purchase-state-machines]]
2. **A public SDK key is not a secret, and saying so out loud prevents worse mistakes.** The reason
   `test_…`/`appl_…` is safe — it can only post receipts that Apple then validates — is exactly the
   reason `sk_…` and the `.p8` are catastrophic. Writing the distinction into the file that holds
   the key is cheaper than re-deriving it under deadline pressure.
3. **StoreKit success ≠ entitlement active.** Ask to Buy defers, and a dashboard product never
   attached to the entitlement completes a purchase that grants nothing. "You're all set" there is a
   lie the user discovers at the next locked feature; the code says "being processed" instead.
4. **Fail open on entitlements, always.** A timeout must never revoke Pro. Honouring a
   just-expired subscription for a few minutes costs nothing; locking out a paying user offline is a
   refund and a one-star review.
5. **Three outcomes, not two.** Cancel is not failure and "nothing to restore" is not failure. App
   Review taps Cancel on every paywall it sees, and an error alert there is a documented rejection
   risk as well as the commonest way a paywall reads as hostile.
6. **Render compliance yourself, under every path.** The remote paywall *can* carry Restore, the
   legal links and the auto-renewal sentence — but whether it does is a dashboard setting editable
   after ship. Compiling the footer in means a dashboard mistake can only ever add a duplicate.
7. **Never write a price down.** Prices, periods, savings and the disclosure sentence all come from
   `StoreProduct`; a literal is wrong in every storefront but one and is a rejection cause. The
   saving badge returns `nil` rather than make a claim the current prices no longer support.
8. **The dashboard is undocumentable from the code.** Products, entitlement, offering, remote paywall
   design, experiment and placements exist only in RevenueCat's UI. [[phase-3-technical]] §7 is the
   only record of it; if that section rots, the phase is unreproducible.
9. **Sandbox reads differently.** `entitlements.active[…]` filters by environment and would report a
   genuinely-purchased Test Store entitlement as inactive — locking the reviewer out of everything
   they were asked to check. `.all[…]?.isActive` is the correct read.
10. **A protocol seam is what makes money code testable.** Eleven tests drive the whole state machine
    with `Purchases` never configured and no network touched, because everything that talks to the
    SDK is a one-line pass-through behind `EntitlementGateway`.

## Monetization

Entitlement `pro`. Free: 3 documents/month, PNG, single page. Pro: unlimited, multi-page PDF, batch,
custom rules, audit log. Targeting the **HAMM award** via depth — remote paywalls, an A/B experiment,
Customer Center, win-back offers — not just a `purchase()` call.

As built in Phase 3 ([[phase-3-technical]]):

- **One purchase state machine**, `Core/Entitlements/EntitlementStore.swift`. `isPro` is written in
  exactly one function, from `entitlements.all[…]?.isActive` (not `.active`, which filters by
  environment and would report a sandbox purchase as inactive).
- **Never poll, never fail closed.** One `customerInfoStream` subscription for the process lifetime;
  a network error keeps whatever Pro status was already known.
- **Cancel is not an error.** `PurchaseResult` has three cases; `RestoreResult` has
  `nothingToRestore` as a non-error outcome.
- **Prices are never literals.** Everything on the paywall is derived from `StoreProduct` at runtime
  (`PaywallPricing`), including the annual saving badge, which returns `nil` rather than make an
  untrue claim.
- **The required-disclosure block is compiled in** (`PaywallLegalFooter`) under *both* the remote and
  native paywall paths, so a dashboard edit can add a duplicate restore button but never remove the
  only one.
- **Dashboard configuration is not in the repo.** Products, the `pro` entitlement, offering
  `default`, the remote paywall design, the A/B experiment and the placements must all exist in
  RevenueCat — see [[phase-3-technical]] §7. The app is inert without them.
- Public SDK key `test_…` is committed deliberately (it ships in every binary and can only post
  receipts Apple then validates). `sk_…`, the `.p8`, Key ID and Issuer ID must never be
  (`CLAUDE.md` rule 9).

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
| [[library-pro-access-seam]] — `\.libraryProAccess` defaults to false and nothing sets it | **resolved in Phase 3** — replaced by `ProAccess`, a `DynamicProperty` reading `EntitlementStore` from the environment; a missing store resolves to *not Pro*, the safe direction |
| [[two-purchase-state-machines]] — `EntitlementStore` and `PaywallStore` both purchased, restored and kept their own `isPro` | **resolved in Phase 3** — `PaywallStore` now owns screen state only and delegates every purchase to the injected `EntitlementStore`; `PaywallExperiment.entitlementIdentifier` forwards to `RevenueCatConfig` so `"pro"` exists once |
| [[paywall-wiring-outside-allowlist]] — the paywall existed but `RouteDestination` still showed the Phase 2 placeholder | **resolved in Phase 3** — `case .paywall(let context)` resolves to `RedactPaywallView(context:entitlements:)`; `FreeTierNoticeView` deleted |
| [[pro-gating-cross-lane-dependencies]] — gating needed two edits outside the `pro-gating` allowlist | **resolved in Phase 3** — the store is installed at the root and read through `ProAccess` |
| [[library-layout-constants-not-tokens]] — five constants live in the feature, not `Token` | open, cosmetic |

Also unfinished from Phase 1: display fonts not bundled (system fallback), contrast unmeasured
(`Token.Text.faint` on `Token.BG.base` is the suspected 4.5:1 failure), and reduce-motion checkable
only in the simulator.

## Phase documentation

| Phase | Technical | Non-technical | For kids |
|---|---|---|---|
| 1 | [[phase-1-technical]] | [[phase-1-non-technical]] | [[phase-1-guide-for-kids]] |
| 2 | [[phase-2-technical]] | [[phase-2-non-technical]] | [[phase-2-guide-for-kids]] |
| 3 | [[phase-3-technical]] | [[phase-3-non-technical]] | [[phase-3-guide-for-kids]] |

## Session log

| Date | Log | Summary |
|---|---|---|
| 2026-08-17 | [[2026-08-17-01]] | Phase 3 — RevenueCat SDK, one entitlement state machine, paywall (remote + native), runtime pricing, compiled-in compliance footer, Pro gating in Scan/Export/Library; verifier found 7 (4 crit/high), fixer applied 9, 3 escalated; **M3 test purchase observed**; triad written ([[phase-3-technical]]) |
| 2026-08-17 | [[2026-08-17-01]] | Phase 0 — harness, memory layer, governance docs; Phase 1 — design system, detection, redaction, persistence; Phase 2 — shared contract, scan, editor, export, library, onboarding; verify + fix; sample-document leak found in the exported pixels and fixed; gate green at 98 tests |
