---
id: phase-2-technical
date: 2026-08-17
phase: 2
audience: engineers
tags: [phase-2, technical, scan, editor, export, library, onboarding, geometry]
status: complete
---

# Phase 2 — Technical Record

> Audience: an engineer who has never seen this repo and must be able to rebuild Phase 2 from
> scratch, or resume it cold.
> Siblings: [[phase-2-non-technical]] · [[phase-2-guide-for-kids]]
> Rules that constrain everything below: `CLAUDE.md`. Current state: [[memory-index]].
> Previous phase: [[phase-1-technical]].

## 1. What Phase 2 was for

Phase 1 built an engine with no car around it: detection, redaction and persistence with no screen
driving them. Phase 2 is the loop — a document goes in as photo, scan or PDF and comes out as a
saved, shareable, genuinely-destroyed file.

Exit criterion from `plan.md`: *"A document goes photo → redacted export, end to end."* It does, and
it was **observed** in the simulator rather than reasoned about: cold launch → three taps → an
editor with eleven detections → two more taps → a PNG in the vault, with the exported bytes pulled
out of the container and inspected pixel by pixel.

| Feature | Owner agent | Files | Status on exit |
|---|---|---|---|
| F06 scan / import | `feature-scan` | `RedactApp/Features/Scan/**` | `in_progress` |
| F07 redaction editor | `feature-editor` | `RedactApp/Features/Editor/**` | `built` |
| F08 export (PNG / PDF) | `feature-export` | `RedactApp/Features/Export/**` | `built` |
| F09 library | `feature-library` | `RedactApp/Features/Library/**` | `built` |
| F11 onboarding + sample | `onboarding` | `RedactApp/Features/Onboarding/**`, `RedactApp/App/**` | **`verified`** |
| — shared contract | `feature-contract` | `RedactApp/Features/Shared/**` | infrastructure, not a feature |

Six agents, one contract agent first and five feature agents in parallel with disjoint allowlists,
then one integrator pass, one verifier pass, one fixer pass — the bounded loop from
[[DEC-005-bounded-loop]]. No agent verified its own work (`CLAUDE.md` rule 7). F11 is the only
feature the verifier promoted; **F03 (detection) lost its `verified` status this phase**, see §7.

Gate on exit: `./verify.sh` exit 0, **98 tests, 0 failures**, app installs, launches and stays alive
on the iOS 26.5 simulator.

## 2. Architecture, with real paths

```
RedactApp/
├─ App/
│  ├─ RedactApp.swift          @main
│  ├─ AppEnvironment.swift     ModelContainer + one shared DocumentStore; prepareStorage()
│  ├─ RootView.swift           NavigationStack(path: $coordinator.path), .ambientBackground()
│  ├─ RouteDestination.swift   the ONE `switch AppRoute` in the app
│  ├─ FreeTierNoticeView.swift what presentPaywall() shows until Phase 3 replaces it
│  └─ LegalLinks.swift         privacy / terms / support URLs  ← UNPUBLISHED, see §9
└─ Features/
   ├─ Shared/                  the Phase 2 contract — read this first
   │  ├─ RedactionSession.swift   session model, undo/redo, activeRegions
   │  ├─ AppRoute.swift           AppRoute + AppCoordinator (+ paywall seam)
   │  ├─ DocumentPipeline.swift   the one Data → pages → OCR → classify → session path
   │  └─ RedactionRegion.swift    EXTENSIONS ONLY (see §3.4)
   ├─ Scan/
   │  ├─ ImportPipeline.swift     camera / photo / PDF → SessionSource
   │  ├─ DocumentCameraView.swift VNDocumentCameraViewController wrapper
   │  └─ ScanView.swift           entry screen, quota gate, cancellable progress
   ├─ Editor/
   │  ├─ EditorMetrics.swift      EditorMetric + DetectionPalette (kind → token)
   │  ├─ EditorGeometry.swift     pure geometry: fit, clamp, snap, hit-target
   │  ├─ ScanlineAnimation.swift  ScanlineDirector + ScanlineSweep + Haptics
   │  ├─ DetectionOverlay.swift   the boxes
   │  ├─ ManualRegionLayer.swift  hand-drawn boxes, handles, VoiceOver resize
   │  ├─ DetectionListSheet.swift the accessible equivalent of the canvas
   │  └─ EditorView.swift         the screen
   ├─ Export/
   │  ├─ AnnotationAudit.swift    inherited-markup detection (the escalated Phase 1 decision)
   │  ├─ InsecureMarkupSheet.swift the offer
   │  ├─ ExportPipeline.swift     session → RedactionEngine → FileVault → DocumentStore
   │  └─ ExportView.swift         preview of the redacted output, format, ShareLink
   ├─ Library/
   │  ├─ LibraryView.swift · DocumentDetailView.swift · LibraryModel.swift
   │  ├─ ThumbnailLoader.swift · DocumentSummary.swift · AuditEntry.swift
   │  └─ LibraryProAccess.swift · LibraryLayout.swift · UndoSnackbar.swift
   └─ Onboarding/
      ├─ SampleDocument.swift     the demo payslip, DRAWN IN CODE
      ├─ OnboardingState.swift · OnboardingView.swift · AboutView.swift
```

New tests: `Tests/ExportTests/AnnotationAuditTests.swift` (7),
`Tests/RedactionTests/SampleDocumentLeakTests.swift` (4),
`Tests/DetectionTests/LabelledFieldDetectorTests.swift`.

### Data flow, end to end

```
camera / PhotosPicker / .fileImporter
   └─► ImportPipeline.makeSource(...)            normalise ONCE, before the session exists
          └─► SessionSource .image(Data) | .pdf(Data)      ← never mutated again
                 └─► RedactionSession(source:title:)
                        └─► DocumentPipeline.run(on:)
                               ├─ renderPages       detached; PDFKit → PNG @2× (or pass-through)
                               ├─ TextRecogniser    per page, Vision
                               └─ PIIClassifier     per page → [SessionDetection]
                        └─► EditorView   toggles / manual boxes / undo → SessionEditState
                               └─► session.activeRegions(onPage:) / pageRedactions()
                                      └─► ExportPipeline.run(...)
                                             ├─ AnnotationAudit (PDF only, pre-export)
                                             ├─ RedactionEngine  ← the ONE destroy path
                                             ├─ FileVault.write
                                             └─ DocumentStore.insert + UsageTracker
                                                    └─► Library / ShareLink
```

Only `Data` and `Sendable` value types cross an isolation boundary anywhere on that path.
`PDFDocument`, `CGImage`, `UIImage`, `VNDocumentCameraScan` are created, used and destroyed inside
one function body. Zero `@unchecked Sendable`, zero `nonisolated(unsafe)` in the whole tree —
grep-verified by the verifier.

## 3. The shared contract (`Features/Shared/**`)

Five feature agents ran in parallel. Anything they *all* needed had to exist first, and it had to be
shaped so that the expensive mistakes were not expressible. Four files.

### 3.1 `RedactionSession` — edits are decisions, not pixels

The single most consequential design choice of the phase: **the source bytes are never mutated.**
The user's work is a set of opt-outs plus a list of drawn rectangles. Destruction happens exactly
once, in `RedactionEngine`, at export, starting from the pristine original.

Three things fall out of that for free:

1. **Undo is a struct swap.** No re-render, no image copy, no diffing.
2. **The preview cannot drift from the export**, because both derive from the same
   `activeRegions(onPage:)`.
3. **There is one destroy path to prove correct**, and `IrreversibilityTests` already attacks it.

```swift
/// The entire user-editable state of a session, as one value.
///
/// Undo/redo is implemented by pushing copies of this struct. That is only cheap because it holds
/// *decisions*, not pixels: a set of opt-outs and a list of drawn rectangles. If anything expensive
/// (page images, source bytes, detection results) is ever added here, undo stops being free — put
/// it on the session instead.
public struct SessionEditState: Sendable, Hashable {
    /// Detections the user chose **not** to redact.
    ///
    /// Stored as opt-outs rather than opt-ins so that the safe state is the default: a detection
    /// that arrives after this set was built is redacted unless the user says otherwise. An
    /// opt-in set would fail open, which for this app means shipping a document with live PII.
    public var disabledDetections: Set<SessionDetectionID>
    public var manualRegions: [ManualRegion]
}
```

**Opt-out, not opt-in, is a security property.** A `Set` of "things the user approved" fails open:
any detection that arrives after the set was built (a re-run, a late page, a new detector) is
silently not redacted. A `Set` of "things the user declined" fails closed. In this app failing open
means shipping live PII.

Every mutation goes through one funnel, which is what makes undo impossible to forget:

```swift
/// The single funnel every edit goes through, so no code path can change state without
/// recording an undo entry. A mutation that leaves the state unchanged records nothing —
/// otherwise tapping a toggle twice would need two undos to get back.
private func mutate(_ change: (inout SessionEditState) -> Void) {
    var updated = editState
    change(&updated)
    guard updated != editState else { return }
    undoStack.append(editState)
    if undoStack.count > undoLimit { undoStack.removeFirst() }
    redoStack.removeAll()
    editState = updated
}
```

And one derivation from "what the user decided" to "what gets burned in":

```swift
/// The regions to destroy on one page: enabled detections plus hand-drawn boxes.
///
/// This is the single derivation from "what the user decided" to "what gets burned in". Export
/// must call this rather than rebuilding the list, so what the editor previewed and what the
/// engine destroys cannot drift apart.
public func activeRegions(onPage pageIndex: Int) -> [RedactionRegion] {
    let fromDetections = detected
        .filter { $0.pageIndex == pageIndex && isEnabled($0) }
        .compactMap { RedactionRegion(detected: $0.pii) }
    return fromDetections + manualRegions(onPage: pageIndex).map(\.region)
}
```

Smaller decisions that earned their place:

- `currentPageIndex` is **clamped on write**, not trusted. A `TabView(selection:)` binding can
  transiently propose an index past the end while `pages` is still filling, and an out-of-range
  index means the editor draws page N's boxes over page M's pixels.
- `setDetections(_:)` intersects `disabledDetections` with the live set, so a stale key from a
  previous run cannot silently suppress a *different* detection later.
- `SessionDetectionID` is `(pageIndex, detectionID)`. `DetectedPII.id` is built from character
  offsets and restarts at zero on page two, so it is unique only within a page.
- `SessionDetection.isRedactable` is false when the span has no OCR geometry. Those are shown as
  informational rows, never as a toggle that does nothing (rule 10).

### 3.2 `AppCoordinator` — a typed stack and a paywall seam with no RevenueCat in it

`path` is `[AppRoute]`, not `NavigationPath`: a mis-typed push is a compile error and the whole
stack can be asserted in a test. `AppRoute.editor`/`.export` carry the live session — it is unsaved
in-memory work with nowhere to look it up from — so `Hashable` is deliberately **identity**:

```swift
case (.editor(let a), .editor(let b)), (.export(let a), .export(let b)):
    return a === b
…
case .editor(let session):
    hasher.combine(3)
    hasher.combine(ObjectIdentifier(session))
```

Value equality would be wrong twice over: the route would change on every toggle, and SwiftUI would
tear the destination down mid-edit.

`AppRoute` is deliberately **not** `Codable`. State restoration would have to resurrect unsaved
document bytes, and a half-restored redaction session is worse than starting again. Finished work is
reached through `.documentDetail(id:)`.

The paywall seam is one method:

```swift
/// The one entry point to the subscription screen.
///
/// Every quota check (`UsageTracker` says the free tier is spent) calls this and nothing else,
/// so Phase 3 changes presentation in one place and no feature has to learn about RevenueCat.
/// No purchase, entitlement, or SDK type appears in this file by design.
public func presentPaywall() {
    presentedSheet = .paywall
}
```

Zero RevenueCat references exist anywhere in `Features/`. Phase 3 (F10) replaces one line in
`RouteDestination` and deletes `FreeTierNoticeView.swift`.

`showExport(for:)` **replaces** the editor entry rather than stacking on it, so "back" after an
export returns home rather than to an editor whose session has been consumed. `finish(savedDocumentID:)`
sets the path to `[.library, .documentDetail(id:)]` and drops the session — its bytes are the
*unredacted* original and holding them after the safe copy is saved is a liability with no benefit.

**Environment delivery.** `@Environment(AppCoordinator.self)`, not a custom `EnvironmentKey`. A key
needs a `nonisolated static var defaultValue`, which a `@MainActor` class can only supply through
`MainActor.assumeIsolated` — a latent crash. The contract agent wrote that version first and removed
it.

### 3.3 `DocumentPipeline` — one path, staged progress, real cancellation

```
@MainActor  session.setProcessing(.recognising)
  detached  render pages   (PDFKit → PNG Data, or the source image as-is)
@MainActor  session.setPages(...)              ← pages visible while OCR is still running
  detached  TextRecogniser.recognise(...)      per page
@MainActor  session.setProcessing(.classifying)
  detached  PIIClassifier.classify(...)        per page
@MainActor  session.setDetections(...) ; .ready
```

- Progress is published **in stages**, so the editor shows page one while page nine is still being
  read.
- Cancellation leaves the session `.idle`, not `.failed` — a cancelled run is not an error the user
  should be told about. Every caller distinguishes the two:

```swift
} catch is CancellationError {
    session.setProcessing(.idle)
} catch {
    session.setProcessing(.failed(error))
}
```

- `pageRasterScale = 2`. Below it Vision misses 8pt print (which is the size a bank account number
  is usually set in); above it a 20-page statement costs hundreds of megabytes of decoded images for
  no accuracy gain.
- `imagePixelSize(of:)` reads dimensions from the **header** via `CGImageSourceCopyPropertiesAtIndex`
  — a 48MP photo would otherwise cost tens of megabytes just to learn its aspect ratio — and
  transposes for orientation tags 5…8, or the editor gets a landscape frame for a portrait page.
- `rasterisePDF` transposes `pointSize` when `abs(page.rotation) % 180 == 90`, **intentionally
  mirroring `RedactionEngine.rasterisedPage`**. If the two disagree, the preview and the export
  disagree about which way is up.
- The classifier is injectable (`classifier: any PIIClassifier = ClassifierFactory.make()`) so tests
  can force the iOS 17 heuristic path per [[DEC-003-ios-target]].

### 3.4 `RedactionRegion.swift` contains no `RedactionRegion`

This file is extensions only, and the comment at the top is load-bearing:

```swift
// MARK: - Why this file contains no `RedactionRegion` declaration
//
// `RedactionRegion`, `PageRedaction`, `RedactionStyle` and `RedactionBarInk` are already declared
// by `Core/Redaction/RedactionStyle.swift`. Everything in this app target compiles into one module,
// so a second declaration of the same name is a redeclaration error, not a shadow — Phase 1 lost
// time to exactly that with two `Models.swift` files. The feature layer therefore *extends* the
// Core type and never restates it.
//
// The one rule every feature agent must respect: `RedactionRegion.rect` is normalised 0...1 with a
// **top-left** origin. `TextSpan.boundingBox` is normalised 0...1 with a **bottom-left** origin.
// The flip lives in exactly two places — `RedactionRegion.init(visionBoundingBox:style:)` and
// `TextSpan.topLeftOriginBoundingBox` — and nowhere else. Do not write `1 - y` in a view.
```

Three extension members are the whole feature-facing geometry API:

```swift
public init?(detected: DetectedPII, padding: CGFloat = 0.004, style: RedactionStyle = .solidBar) {
    guard detected.span.hasGeometry else { return nil }
    var region = RedactionRegion(visionBoundingBox: detected.span.boundingBox, style: style)
    region.rect = region.rect.insetBy(dx: -padding, dy: -padding).clampedToUnitSquare()
    guard !region.rect.isEmpty else { return nil }
    self = region
}

public init?(userDrawnRect rect: CGRect, in imageSize: CGSize, style: RedactionStyle = .solidBar)

/// The region in points for a view of `size`, top-left origin — ready for SwiftUI `.offset`
/// or a `Path`, with no further flipping.
public func displayRect(in size: CGSize) -> CGRect
```

`displayRect(in:)` is deliberately distinct from Core's `pixelRect(in:)`: Core rounds **outward**
because it is feeding a pixel buffer; display wants the exact fractional rect, because rounding it
would make the preview disagree with the export by up to a pixel at every zoom level.

Result: **no feature file in Phase 2 contains a `1 - y`.** Even `AnnotationAudit`, which converts a
PDF page rect (points, bottom-left) to normalised top-left, delegates:

```swift
/// The flip is not written here. It is delegated to Core's
/// `RedactionRegion.init(visionBoundingBox:style:)`, which is one of the two functions in the
/// whole app allowed to contain a `1 - y`. Vision boxes and PDF page rects share the same
/// bottom-left convention once normalised, so the existing conversion is the correct one — and
/// reusing it means a fix there fixes every caller.
private static func normalisedTopLeftRect(of rect: CGRect, in pageBox: CGRect) -> CGRect {
    let bottomLeftNormalised = CGRect(
        x: (rect.minX - pageBox.minX) / pageBox.width,
        y: (rect.minY - pageBox.minY) / pageBox.height,
        width: rect.width / pageBox.width,
        height: rect.height / pageBox.height
    )
    return RedactionRegion(visionBoundingBox: bottomLeftNormalised).rect.clampedToUnitSquare()
}
```

## 4. Scan / import (F06)

Three routes in, one `SessionSource` out.

**Normalise before the session exists.** The bytes in `SessionSource` are simultaneously what Vision
reads and what `RedactionEngine` later destroys. If those two differ by so much as a resample, a bar
lands in the wrong place and the export leaks. So the only resampling (above 36 MP) happens in
`ImportPipeline`, before anyone sees the document, with
`kCGImageSourceCreateThumbnailWithTransform: true` so EXIF orientation is baked rather than left as
a tag on new bytes. Rejected: re-encoding every import to PNG "for uniformity" (changes the pixels
Vision reads for no benefit), and downsampling after session creation (preview and export disagree).

**Multi-page camera capture becomes a PDF.** `SessionSource` has no multi-image case. Inventing one
would mean a second page-indexing scheme alongside `PageRedaction.pageIndex`. A PDF already *is* the
multi-page container the rest of the app understands, and `DocumentPipeline` rasterises it straight
back.

**Photos: `PhotosPicker` only.** No `PHPhotoLibrary.requestAuthorization` anywhere in the tree
(grep-verified). The picker is out-of-process and returns just the picked item, so full-library
authorisation buys nothing and is an App Review finding.

**The quota gate is in front of the work, not behind it:**

```swift
private func begin(_ action: Action) {
    failure = nil
    guard usage.canProcessDocument() else {
        coordinator.presentPaywall()
        return
    }
    …
}
```

Letting someone capture eight pages and wait through recognition before saying "you're out" reads as
a bait-and-switch.

**Import and detection are ONE task**, so Cancel genuinely stops the OCR loop rather than hiding a
spinner over work that keeps running:

```swift
work = Task { @MainActor in
    do {
        let source = try await makeSource()
        try Task.checkCancellation()

        let newSession = RedactionSession(source: source, title: title)
        session = newSession
        stage = .working

        await DocumentPipeline.run(on: newSession)
        try Task.checkCancellation()

        if let error = newSession.processing.error {
            fail(error)
        } else if newSession.processing.isReady {
            coordinator.push(.editor(newSession))
            reset()
        } else {
            reset()   // `.idle` — the pipeline absorbed a cancellation. Not an error.
        }
    } catch is CancellationError {
        reset()
    } catch {
        fail(error)
    }
}
```

**The VisionKit isolation fight.** The camera delegate began as `nonisolated` witnesses calling
`MainActor.assumeIsolated`. That does not compile under Swift 6: `VNDocumentCameraScan` is not
`Sendable` and cannot be captured into the closure. The integrator's fix was to drop the nonisolated
witnesses entirely — the `Coordinator` is already `@MainActor` — and conform with
`@preconcurrency VNDocumentCameraViewControllerDelegate`, which is what "documented main-thread
callback" actually means to the compiler. Worth copying: `@preconcurrency` on the conformance is the
supported expression of that guarantee; `assumeIsolated` is not, once a non-`Sendable` value is
involved.

F06 is still `in_progress` in `feature_list.json` — its agent declined to write `built` for code it
had not compiled, and nobody re-rated it after the integrator's build went green. That is
conservative, not wrong.

## 5. The editor (F07)

### 5.1 The scanline reveal — the stagger is geometric, not scheduled

[[DEC-002-design-language]] calls this "the screenshot that wins or loses the Design Award", so the
mechanism matters. There is **no per-box timer**. One animated `Double` sweeps 0→1 down the page and
each box reveals itself when the sweep passes its own normalised midpoint.

```swift
/// Runs the reveal. Idempotent: the second call is a no-op.
///
/// - Parameter reduceMotion: read from the environment by the caller. Passed in rather than read
///   here because an `@Observable` model has no environment, and inventing one would put the
///   accessibility decision somewhere a reviewer cannot see it.
func reveal(reduceMotion: Bool) async {
    guard !hasRun else { return }
    hasRun = true

    guard !reduceMotion else {
        withAnimation(Motion.crossFade) {
            progress = 1
            hasLanded = true
        }
        return
    }

    isSweeping = true
    withAnimation(Motion.meter) { progress = 1 }

    try? await Task.sleep(nanoseconds: UInt64(sweepDuration * 1_000_000_000))
    guard !Task.isCancelled else { return }

    isSweeping = false
    land()
}

private func land() {
    withAnimation(Motion.standard) { hasLanded = true }
    Haptics.barsLanded()
}

/// True when the sweep has passed a detection sitting at `normalisedMidY` down the page.
func hasReached(_ normalisedMidY: CGFloat) -> Bool {
    hasLanded || progress >= Double(normalisedMidY)
}
```

```swift
// DetectionOverlay.Item — where the stagger comes from
var revealThreshold: CGFloat { region.rect.midY }
```

Rejected alternative: a per-box `Task.sleep` ladder. It needs a timer per detection, it
desynchronises if the layout changes mid-sweep, and it must be torn down on cancellation. The
comparison gives the same staircase for free, in reading order, and stays correct if a detection is
added or removed while the sweep is running.

Three accessibility properties, all in that one function:

- Under reduced motion `progress` jumps to 1 under `Motion.crossFade`, the band is never drawn, and
  **`Haptics.barsLanded()` is never reached**. A user who asked the system to calm down should not be
  punched in the hand by a vestibular-safe UI.
- `hasRun` makes it idempotent. Re-entering the editor or a stray view rebuild must not replay a
  reveal; a reveal that repeats reads as a glitch.
- Any touch calls `settleImmediately()`. **An animation is never a gate on a control.**

### 5.2 Geometry that is pure, and hit targets that are not the drawn box

`EditorGeometry` is a struct-free namespace of pure functions — no view, no state, no `1 - y` —
specifically so `Tests/` can cover it without a view host (that test file does not exist yet; see
§9).

```swift
static func hitSize(for rect: CGRect, zoom: CGFloat) -> CGSize {
    let minimum = Token.Size.minimumHitTarget / max(zoom, EditorMetric.minimumZoom)
    return CGSize(width: max(rect.width, minimum), height: max(rect.height, minimum))
}

static func snapped(_ rect: CGRect, to candidates: [CGRect],
                    threshold: CGFloat = EditorMetric.snapDistance) -> CGRect {
    guard !candidates.isEmpty else { return rect }
    let nearby = candidates.filter { $0.intersects(rect.insetBy(dx: -threshold, dy: -threshold)) }
    guard !nearby.isEmpty else { return rect }
    let left = nearest(rect.minX, in: nearby.map(\.minX), threshold: threshold) ?? rect.minX
    let right = nearest(rect.maxX, in: nearby.map(\.maxX), threshold: threshold) ?? rect.maxX
    let top = nearest(rect.minY, in: nearby.map(\.minY), threshold: threshold) ?? rect.minY
    let bottom = nearest(rect.maxY, in: nearby.map(\.maxY), threshold: threshold) ?? rect.maxY
    let snapped = CGRect(x: left, y: top, width: right - left, height: bottom - top)
    return snapped.width > 0 && snapped.height > 0 ? snapped : rect
}
```

Two points worth stealing. The hit target grows to 44pt **about the box's own centre and divided by
the zoom factor**, so it does not swallow neighbours when magnified, while the drawn outline still
tracks the text exactly — without this a PAN set in 8pt type is untappable. And **snapping is
correctness, not polish**: a finger-drawn box over an 8pt line clips ascenders, and a clipped glyph
is a legible glyph.

The draw gesture is attached *inside* the `scaleEffect`, so gesture points arrive already in content
points and no call site inverts a transform. The two draw modes are separated by a hit-testing mask
rather than by branching the view tree:

```swift
.gesture(holdToDrawGesture(contentSize: contentSize),
         including: isDrawMode ? .subviews : .all)
.gesture(drawGesture(contentSize: contentSize),
         including: isDrawMode ? .all : .subviews)
```

### 5.3 State without colour, and a list that is not a convenience

Enabled = solid stroke + fill + `checkmark.circle.fill`. Disabled = dashed hairline + empty +
`circle.dashed`. Colour encodes only the *category*, so the enabled/disabled distinction survives
greyscale and colour blindness (rule 4).

`DetectionListSheet` is **the accessible path, not a convenience**: tapping a 6pt rectangle on a
zoomed canvas is impossible with VoiceOver, so every canvas decision is also a labelled row with a
switch. `EditorSummary` is the single source of the "N items found · M will be removed" wording,
shared by canvas and sheet, so the two cannot disagree.

## 6. Export (F08) — and the answer to Phase 1's escalated question

Phase 1 escalated [[pdf-passthrough-pages-keep-annotations]]: `redactedPDFData` inserts region-free
pages verbatim, annotations included, so a fake black box drawn by *another* tool ships intact. The
human chose **detect and offer**. Never silently flatten (it destroys selectable text on pages the
user never touched); never silently strip (it discards real signatures and comments).

### 6.1 `AnnotationAudit` — the discriminator is "is there text underneath"

Filtering on annotation subtype alone would fire on every signed contract. The verifier singled this
out as the correct part of the phase, so the reasoning is worth quoting from the source:

```swift
/// The text a reader would recover by deleting the mark.
///
/// This is the whole discriminator. A signature over a blank line and a black box over an
/// account number are the same object to PDFKit; the only thing that separates a harmless
/// comment from a peel-off fake redaction is whether the page still has glyphs underneath.
/// Getting this wrong in the permissive direction is not a cosmetic bug: a warning that fires on
/// every signed contract teaches the user to tap through it, and the one document that really is
/// leaking gets tapped through too.
private static func extractableText(under rect: CGRect, on page: PDFPage) -> String {
    guard let selection = page.selection(for: rect) else { return "" }
    return selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}
```

Three filters in series, each removing a different class of false alarm:

1. **Subtype** — square, `/Redact`, ink, highlight, freeText, popup. Not links, form fields or
   stamps: those do not conceal running text.
2. **Opacity**, per type. `.highlight` needs 0.9 (the standard yellow one multiplies and text under
   it stays perfectly readable); everything else 0.6. An unfilled square is a *frame* — the text
   inside it is plainly visible and warning about it is noise. A `/Redact` annotation skips the
   opacity test entirely: some tool marked content for removal and never applied it, which is a leak
   however it is painted.
3. **Extractable text under the bounds.** Marks that pass 1 and 2 but hide nothing land in
   `benignMarkupPageIndices` — recorded so the export screen does not claim the file has no markup
   at all, never surfaced as a warning.

`PDFKit` ships no `PDFAnnotationSubtype.redact` constant (an integrator finding), so the subtype is
matched by raw-value suffix. `PDFAnnotation.type` is observed both with and without a leading
solidus depending on construction, so the name is normalised before matching — a miss here is a
warning that never fires.

**No sample of hidden text is ever stored.** `Finding` carries `hiddenCharacterCount`, never the
words. Copying "what we found under the box" into a report, and then into a warning sheet, would
re-expose exactly what the user is protecting (rule 2).

`audit(pdfData:)` scans **every** page, including pages about to be redacted anyway. The alternative
is a report whose contents depend on what the user happened to select, which would make the warning
appear and disappear as they toggled detections in the editor.

### 6.2 Flattening expressed as a zero-sized region

```swift
static func pageRedactions(
    for session: RedactionSession,
    flattening pagesToFlatten: FlattenSelection
) -> [PageRedaction] {
    var byPage: [Int: [RedactionRegion]] = [:]
    for redaction in session.pageRedactions() {
        byPage[redaction.pageIndex, default: []] += redaction.regions
    }
    for pageIndex in pagesToFlatten where byPage[pageIndex] == nil {
        byPage[pageIndex] = [flattenOnlyRegion]
    }
    return byPage.sorted { $0.key < $1.key }.map { PageRedaction(pageIndex: $0.key, regions: $0.value) }
}

static let flattenOnlyRegion = RedactionRegion(rect: .zero)
```

`RedactionEngine.redactedPDFData` already rebuilds from pixels any page carrying at least one
region, and `burnBars` skips regions whose pixel rect is empty. So a zero-sized region says
"rasterise this page, destroy nothing extra" **through the one audited destroy path**. A second
rasteriser inside Export would be a second thing to prove correct, and `IrreversibilityTests` only
attacks the first one.

### 6.3 Ordering in `ExportPipeline.run`

The ordering is the safety property, so read it in order: format/quota/emptiness guards → capture
**every** input as `Sendable` values on the main actor → detach → write file → write thumbnail →
insert record → bump the counter.

```swift
// Everything the engine needs is captured as `Sendable` values here, on the main actor,
// before any work is detached. Nothing reaches back into the session from the detached
// task, so there is no way for a mid-export edit to change what gets destroyed.
```

- **Quota is consumed after success.** A failed or cancelled export never costs the user a document.
- **Cancellation is checked between stages only.** Past the point where bytes exist on disk the
  remaining work runs to completion, because cancelling there would orphan them.
- The preview goes through `RedactionEngine` too (`previewImageData`), not through a SwiftUI overlay
  — *"A preview drawn separately can agree with the export today and drift from it tomorrow, and the
  direction it drifts in is a bar that looks right on screen and lands elsewhere in the file."*
- `kindIdentifier(for:)` is a hand-written switch, not `String(describing:)`, because the audit trail
  is persisted and renaming an enum case must not rewrite history.

## 7. The verifier pass, and the leak it found

The verifier ran `./verify.sh` (exit 0), then installed the built `.app` on the booted iOS 26.5
simulator and **drove it by screenshot** — because compiling is not running, and the previous four
sessions had all stopped at the compile line.

**Reviewer path, observed:** cold launch → Continue → Continue → **Try it on a sample document** =
3 taps to an editor with detections already marked, ~20 seconds, no camera, no photo permission, no
account, no typing. Two more taps produce a saved PNG; the free counter went 3 → 2. That is F11's
acceptance criterion, met and observed; F11 is the only feature promoted to `verified` this pass.

Then it pulled the exported file straight out of the container
(`Library/Application Support/RedactVault/Pages/*.png`, 2000×2828) and **looked at the pixels**:

```
Employee   Ananya Mehra          <- no bar at all
Date of Birth: 1███████          <- leading digit of 14/03/1994 survives
IFSC: Z███████                   <- leading character survives
```

…while the screen above it said "10 removed" and "There is nothing underneath them to recover."

**This is why F03 lost `verified`.** Its unit tests pass honestly — they assert monotonicity and
containment — but nothing in the suite compared a projected box against real OCR of a real render,
so the suite could not see it. `feature_list.json` was left untouched by the fixer (rule 7: it may
not write `verified`), so F03, F07, F08 all need the verifier's next pass to re-rate.

### 7.1 One symptom, two defects

The fixer drove the pipeline before changing anything, which is the entire reason the fix is
correct: the reported cause explained only half the leak.

**7.1a — the name was never detected at all.** `NLTagger(.nameType)` returns *nothing* for the bare
string `Employee Ananya Mehra`. It is a prose model with no sentence to work with. And OCR reads the
sample's two-column block as a stack (`Employee` / `Ananya Mehra` on separate lines), so no
single-line detector could ever have paired them. The "personName" bar the verifier saw sitting on
the word "August" was not a drifted name bar — it was a separate, genuine NLTagger false positive on
the page title.

Fix: `RedactApp/Core/Detection/LabelledFieldDetector.swift`. **A printed label is evidence, in every
language** — which is precisely what a model trained on Western prose is not. Inline (`Employee: X`)
and stacked (via `HeuristicClassifier.labelledNamesAcrossLines`) both handled. The label set is
deliberately narrow: `Designation` and `Employee ID` are excluded, because bars over job titles
teach users to switch bars off.

**7.1b — the geometry drift was real.** `HeuristicClassifier.subBox` split a Vision *line* box by
character **count**, so with proportional type every sub-span drifts right; the numeric spans lost
their first glyph. The `padding: 0.004` (~8px at this render) is an order of magnitude too small to
absorb that.

Fix: use Vision's own measurement. `TextRecogniser` now calls `VNRecognizedText.boundingBox(for:)`
once per character and carries the result in a new `TextSpan.characterBoxes`; `HeuristicClassifier`
prefers it and keeps `subBox` only as a fallback.

**That immediately produced a worse bug**: a bar over the entire top half of the page. Asked for the
box of a lone space, Vision does not throw — it returns a quad spanning most of the page. Every
identifier on the sample contains a space. Hence the two rejections in the final code:

```swift
// TextRecogniser.swift — the two answers Vision gives that must be thrown away
static func characterBoxes(of candidate: VNRecognizedText, within lineBox: CGRect) -> [CGRect] {
    var boxes: [CGRect] = []
    var index = string.startIndex
    while index < string.endIndex {
        let next = string.index(after: index)
        let character = string[index ..< next]
        var box = CGRect.zero
        if !character.allSatisfy(\.isWhitespace),
           let measured = (try? candidate.boundingBox(for: index ..< next))?.boundingBox,
           isPlausible(measured, within: lineBox) {
            box = measured
        }
        for _ in 0 ..< character.utf16.count { boxes.append(box) }
        index = next
    }
    return boxes
}
```

Note `for _ in 0 ..< character.utf16.count` — the array stays UTF-16-indexed so it aligns with
`NSRange`-based span offsets rather than Character offsets.

### 7.2 The generalisable lesson: OCR is a blind oracle for one-character leaks

The fixer's first end-to-end test **passed on the broken build**, and was nearly shipped as proof.
Reverting the fix and re-running is what caught it. The reason is worth carrying into every future
test:

> Vision discards a lone glyph stranded against a black bar. An export that visibly renders
> `Date of Birth: 1` is reported by OCR as `Date of Birth:`.

Every text-level assertion is blind to a one-character leak — which is the leak that matters most,
because a leading digit narrows a guess enormously. So the oracle became **pixels**:
`Tests/RedactionTests/SampleDocumentLeakTests.swift::testEveryPixelOfASecretIsCoveredInTheExport`
uses Vision's own per-character measurement of the *source* as ground truth and asserts the export
is one flat colour across that footprint. It was confirmed to fail on the old geometry before being
kept.

This generalises beyond the sample: **any test that judges redaction by OCR alone can miss a
one-character leak.** Other documents should be spot-checked at the pixel level.

Also fixed in that pass: `exportedMarkupReport` now narrows the audit to the pages the chosen format
actually writes, so a PNG export (which ships only the current page) no longer offers to make page 3
"permanent"; and `Token.Size.thumbnailSmall` replaced a literal, referenced through `@ScaledMetric`.

## 8. Commands — real input, real output

Contract, parse-only (the contract agent could not build; five agents were writing concurrently):

```bash
$ swiftc -parse RedactApp/Features/Shared/*.swift && echo PARSE_OK
PARSE_OK
```

Per-feature typecheck against the real SDK (the form that actually catches things — the plain
`swiftc -parse` above is **syntax only**):

```bash
$ xcrun swiftc -typecheck -swift-version 6 -strict-concurrency=complete \
    -sdk $(xcrun --sdk iphonesimulator --show-sdk-path) \
    -target arm64-apple-ios17.0-simulator $(find snap2 -name '*.swift')
snap2/Features/Shared/RedactionSession.swift:36:30: error: type 'DocumentSourceKind' has no member 'image'
```

That single error was found independently by three agents and written up three times
([[session-source-kind-image-case-missing]], [[session-source-kind-does-not-compile]],
[[session-source-kind-image-vs-photo]]) rather than fixed out of scope. The integrator applied
`case .image: return .photo` — no new enum case, so persisted raw values are unchanged.

The detection probe that proved the sample document actually demos something, run against the real
Phase 1 detectors compiled standalone:

```bash
$ xcrun swiftc -swift-version 5 -o ob/run ob/main.swift \
    RedactApp/Core/Detection/{Models,Checksums,PatternDetector,NameDetector}.swift
$ ./ob/run
  HIT    Date of Birth: 14/03/1994  ->  dateOfBirth=14/03/1994
  HIT    PAN AZZPQ4821K  ->  pan=AZZPQ4821K
  HIT    Aadhaar 9999 8888 7779  ->  aadhaar=9999 8888 7779
  HIT    Mobile +91 90000 12345  ->  phone=+91 90000 12345
  HIT    Email ananya.mehra@example.com  ->  email=ananya.mehra@example.com
  HIT    IFSC: ZZZZ0123456  ->  ifsc=ZZZZ0123456
        -  Basic Salary ₹ 62,500.00
        -  Gross Pay ₹ 1,25,000.00
  NER     ["personName=Ananya Mehra", "place=Northwind", "place=Bengaluru"]
```

Zero false positives on the currency amounts, which was the risk — `₹ 1,25,000.00` is digit-dense.

The diagnostic that reframed the verifier's finding:

```bash
$ xcodebuild test -only-testing:RedactAppTests/TempDumpTests   # temporary, since deleted
DUMPED detections: ["place:Northwind", "personName:Whitefield", "organisation:Bengaluru",
 "personName:August", "pan:AZZPQ4821K", "aadhaar:9999 8888 7779", "phone:+91 90000 12345",
 "dateOfBirth:14/03/1994", "email:ananya.mehra@example.com", "ifsc:ZZZZ0123456"]
# ten items, no name. after LabelledFieldDetector: eleven, including personName:Ananya Mehra
```

Proof the new pixel test is not vacuous — geometry fix deliberately reverted:

```bash
$ xcodebuild test -only-testing:.../testEveryPixelOfASecretIsCoveredInTheExport
XCTAssertEqual failed: ("6") is not equal to ("1") - "14/03/1994" (dateOfBirth) is not fully
covered in the export: 6 distinct colours inside the area Vision measured for it
XCTAssertEqual failed: ("3") is not equal to ("1") - "ZZZZ0123456" (ifsc) ...
Test Case '...testEveryPixelOfASecretIsCoveredInTheExport' failed (2.049 seconds)
# restored, then: passed (1.982 seconds)
```

The gate:

```bash
$ ./verify.sh
  ✓ no key material tracked
  ✓ no networking outside RevenueCat
  ✓ no placeholder strings in user-facing code
  ✓ build succeeded
  ✓ tests passed          # Executed 98 tests, with 0 failures
  ✓ session log exists for 2026-08-17
  ✓ memory index rebuilt
━━━ GATE PASSED ━━━   (exit 0)
```

Driving the built app (the Simulator MCP is still blocked by `xcode-select`, [[gotcha-xcode-select]]):

```bash
$ xcrun simctl uninstall booted com.senthilnathanraja.redact
$ xcrun simctl install booted <DerivedData>/Build/Products/Debug-iphonesimulator/RedactApp.app
$ xcrun simctl launch booted com.senthilnathanraja.redact
$ xcrun simctl io booted screenshot out.png
# and the part that mattered — read the artifact, not the screen:
$ xcrun simctl get_app_container booted com.senthilnathanraja.redact data
$ open "<container>/Library/Application Support/RedactVault/Pages/"*.png
```

A grep gate lesson from this phase, worth remembering:

```bash
$ grep -rnE 'URLSession|URLRequest|NWConnection|CFNetwork' RedactApp/App RedactApp/Features/Onboarding
$ grep -rniE '"(coming soon|lorem ipsum|TODO|FIXME|placeholder)' RedactApp/App RedactApp/Features/Onboarding
CLEAN
```

Both initially matched — inside *doc comments* explaining why the app does neither of those things.
`verify.sh`'s greps are not comment-aware. A comment about a banned API is indistinguishable from
the banned API to a `grep` gate.

## 9. What is incomplete — read this before trusting the phase

1. **The three legal URLs are not published.** `RedactApp/App/LegalLinks.swift` points
   `privacyPolicy`, `termsOfUse` and `support` at `https://senthilnathanraja.github.io/redact/*` and
   **none of those pages exists**. App Store Connect validates the privacy policy URL as *metadata*,
   before a human reviewer ever opens the build, so a 404 burns a review cycle against the
   2026-09-05 deadline. **No code change is correct here** — the human must publish the three GitHub
   Pages and confirm a 200. [[legal-urls-not-published]]
2. **`NLTagger` tags "August" in "Salary Slip — August 2026" as a `personName`**, so the demo burns a
   bar over the page title's month. Over-redaction, not a leak; user-switchable and listed in the
   detection sheet. Left alone deliberately: suppressing month names carries its own false-negative
   risk (people are named August), and a one-pass fixer widening detection rules unprompted is scope
   creep. Needs a decision from whoever owns `detect-engine`. [[nltagger-misses-names-on-forms]]
3. **F03, F07, F08 need re-rating.** F03 was revoked by the verifier; F07 and F08 draw on the
   geometry the fixer changed. The fixer may not write `verified`, so `feature_list.json` is
   untouched and those entries await the verifier's next pass. F06 is still `in_progress` for the
   same class of reason.
4. **Resizing a manual box costs two undo steps.** The fix is a four-line
   `updateManualRegion(id:to:)` on `RedactionSession`, outside the editor agent's allowlist.
   [[manual-region-resize-undo]]
5. **`\.libraryProAccess` defaults to `false` and nothing sets it**, so the Pro audit log is locked
   for everyone until Phase 3. [[library-pro-access-seam]]
6. **Five layout/decode constants live in `LibraryLayout` rather than in `Token`**, because
   `DesignSystem/**` was another agent's scope. [[library-layout-constants-not-tokens]]
7. **`EditorGeometry` has no tests.** It was written pure specifically so `fittedSize`, `clampedPan`,
   `snapped` and `hitSize` could be covered without a view host; `Tests/**` was not in the editor
   agent's allowlist. That is the cheapest test debt in the repo to pay off.
8. **VoiceOver and largest Dynamic Type have not been driven.** Specifically unverified: that the
   library's swipe-delete custom action is reachable from the rotor, and that the undo snackbar is
   announced before it disappears.
9. **Camera capture is untestable in the Simulator** by definition. `DocumentCameraView.isSupported`
   is false there and the row renders disabled with an explanation — which *is* testable.
10. **Everything inherited from Phase 1 is still open**: `FoundationModelClassifier` does no LLM
    reasoning, display fonts are not bundled, contrast is unmeasured, and the Simulator MCP still
    needs a human `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

## 10. Failure modes

| Failure | Symptom | Where it is caught |
|---|---|---|
| Sub-span box interpolated by character count | Bar drifts right; leading glyph of every ID survives | **Was shipped.** Now Vision's `boundingBox(for:)` per character + `SampleDocumentLeakTests` pixel oracle |
| Vision asked for the box of a whitespace character | Quad spanning most of the page; giant bar | Whitespace never queried; `isPlausible(_:within:)` rejects boxes outside their line box |
| Judging a redaction by OCR alone | One-character leak reported as clean | Pixel oracle; OCR assertions kept only as controls |
| Session mutated mid-export | Export destroys something different from the preview | All inputs captured as `Sendable` values on the main actor before detaching |
| Preview drawn as a SwiftUI overlay | Preview and file drift; bar looks right, lands elsewhere | `previewImageData` routes through `RedactionEngine` |
| Opt-in approval set | A late detection is silently not redacted | `disabledDetections` stores opt-**outs** |
| `1 - y` written in a view | Bar on the wrong line | Not expressible: only `RedactionRegion(detected:)`/`(userDrawnRect:)` exist to features |
| PDF page rotation handled differently in preview vs export | Preview and export disagree about "up" | `rasterisePDF` mirrors `RedactionEngine.rasterisedPage`; both transpose at `abs(rotation) % 180 == 90` |
| Quota consumed before success | A failed export costs the user a document | `usage.recordDocumentProcessed()` runs last |
| Cancel after bytes hit disk | Orphaned vault file | Cancellation checked only before/between stages |
| Markup warning fires on every signed contract | Users tap through the one that matters | `page.selection(for:)` text-underneath discriminator + `benignMarkupPageIndices` |
| Markup sheet offered for pages a PNG export will not write | Copy promises page 3 is "made permanent" when it is not in the output | `exportedMarkupReport` intersects with the chosen format |
| Hidden text sampled into a report | The warning re-exposes what the user is protecting | `Finding` stores a character count only |
| Delete leaves files behind | Redacted content survives a "delete" | `LibraryModel.commit` → `DocumentStore.delete` → `FileVault.delete`; window force-closed on background |
| Route made `Codable` | Half-restored session over unsaved bytes | `AppRoute` is deliberately not `Codable` |
| Doc comment mentioning a banned API | `verify.sh` grep gate fails on prose | Reworded; greps are not comment-aware |

## 11. How to replicate this phase from scratch

1. `./init.sh` — read `CLAUDE.md`, then `docs/memory.md`, then `AGENTS.md`.
2. **Build the shared contract first, alone.** One agent, `Features/Shared/**`, no UI. Everything
   five parallel agents need — session, routes, pipeline, geometry API — must exist before any of
   them starts, and the geometry API must make the coordinate flip inexpressible at call sites.
3. Extend Core types; never restate them. One module means a second declaration is a redeclaration
   error.
4. Run the five feature agents in parallel with disjoint allowlists. Each writes its memory entry as
   it works. A compile error in someone else's file is a `gotchas/` note, not a fix.
5. Integrate: `xcodegen generate && ./verify.sh`. Expect a handful of isolation errors at the
   framework seams (VisionKit delegates, main-actor state read from nonisolated error strings) and
   fix them minimally — no refactors.
6. **Verify by driving the built app, not by reading the diff.** Install it, tap through the reviewer
   path, then pull the exported artifact out of the container and look at the pixels. Four previous
   sessions stopped at the compile line and the leak survived all four.
7. One fixer pass. Before changing anything the fixer *drives the pipeline* to confirm the
   attribution — here the reported cause explained half the defect.
8. Write any new end-to-end test, then **revert the fix and confirm the test fails.** A test that
   passes on the broken build is worse than no test.
9. Write the triad, update `docs/memory.md` and `plan.md`, `python3 tools/memory_index.py build`.

**Related:** [[phase-1-technical]] · [[phase-2-non-technical]] · [[phase-2-guide-for-kids]] ·
[[DEC-002-design-language]] · [[DEC-003-ios-target]] · [[DEC-004-no-network]] ·
[[DEC-005-bounded-loop]] · [[pdf-passthrough-pages-keep-annotations]] ·
[[vision-per-character-geometry]] · [[nltagger-misses-names-on-forms]] ·
[[legal-urls-not-published]] · [[2026-08-17-01]]
