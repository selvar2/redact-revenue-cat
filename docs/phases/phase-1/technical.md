---
id: phase-1-technical
date: 2026-08-17
phase: 1
audience: engineers
tags: [phase-1, technical, detection, redaction, design-system, persistence]
status: complete
---

# Phase 1 — Technical Record

> Audience: an engineer who has never seen this repo and must be able to rebuild Phase 1 from
> scratch, or resume it cold.
> Siblings: [[phase-1-non-technical]] · [[phase-1-guide-for-kids]]
> Rules that constrain everything below: `CLAUDE.md`. Current state: [[memory-index]].

## 1. What Phase 1 was for

Phase 0 produced governance and a scaffold. Phase 1 produced the parts of the product that have to
be *correct* before any screen is worth building:

| Feature | Owner agent | Files | Status on exit |
|---|---|---|---|
| F02 design system | `design-system` | `RedactApp/DesignSystem/**` | `built` |
| F03 PII detection engine | `detect-engine` | `RedactApp/Core/Detection/**` | **`verified`** |
| F04 irreversible redaction core | `redaction-core` | `RedactApp/Core/Redaction/**` | `built` |
| F05 SwiftData persistence | `persistence` | `RedactApp/Core/Persistence/**` | `built` |

Exit criteria from `plan.md`: *"Irreversibility test passes; token gallery renders."* Both are met.

Four builder agents ran **in parallel**, each with a file allowlist from `AGENTS.md`, then one
integrator pass, one verifier pass, one fixer pass — the bounded loop from
[[DEC-005-bounded-loop]]. No agent verified its own work (`CLAUDE.md` rule 7).

## 2. Architecture, with real paths

```
RedactApp/
├─ App/
│  ├─ RedactApp.swift            @main, ModelContainer + FileVault wiring
│  └─ RootView.swift             first screen; adopts tokens + typography
├─ DesignSystem/
│  ├─ Tokens.swift               colour / radius / space / shadow / size / alpha  ← law
│  ├─ Typography.swift           11-step scale, .typeStyle(_:) modifier
│  ├─ Motion.swift               curves + reduce-motion guardrail
│  ├─ Surfaces.swift             GlassCard, .glassCard(), .glassCapsule()
│  ├─ AmbientBackground.swift    radial glow field
│  ├─ TokenGallery.swift         every token/surface/component on one page
│  └─ Components/                PrimaryButton, SecondaryButton, Pill,
│                                SectionHeader, IconWell
└─ Core/
   ├─ Detection/
   │  ├─ Models.swift            PIIKind, TextSpan, DetectedPII, overlap resolution
   │  ├─ Checksums.swift         Verhoeff (Aadhaar), Luhn (cards), GSTIN base-36
   │  ├─ PatternDetector.swift   9 checksum-backed regex rules
   │  ├─ NameDetector.swift      NLTagger .nameType NER
   │  ├─ PIIClassifier.swift     protocol + Heuristic + FoundationModel + factory
   │  └─ TextRecogniser.swift    Vision OCR → RecognisedText (text + spans)
   ├─ Redaction/
   │  ├─ RedactionStyle.swift    style, security level, region, page redaction, errors
   │  ├─ RedactionEngine.swift   the destroy path (images + PDFs)
   │  └─ MetadataStripper.swift  decode/encode writer; EXIF/GPS/XMP//Info removal
   └─ Persistence/
      ├─ PersistenceModels.swift @Model RedactedDocument, RedactionRecord
      ├─ DocumentStore.swift     @MainActor facade over ModelContext
      ├─ FileVault.swift         on-disk artefacts, backup-excluded, escape-checked
      └─ UsageTracker.swift      free-tier quota counting
```

Tests mirror it: `Tests/DetectionTests/**`, `Tests/RedactionTests/**`,
`Tests/PersistenceTests/**`, `Tests/DesignSystemTests.swift`.

### Data flow, end to end

```
Data (image/PDF bytes)
   └─► TextRecogniser.recognise(imageData:orientation:)          [Vision, detached Task]
          └─► RecognisedText { text: String, spans: [TextSpan] }  spans: Vision-space boxes
                 └─► PIIClassifier.classify(_ candidates:)        [Heuristic or FM-gated]
                        ├─ PatternDetector.detect(in:boundingBoxProvider:)   checksummed IDs
                        └─ NameDetector.detect(in:boundingBoxProvider:)      NLTagger NER
                              └─► [DetectedPII]  (overlaps resolved)
                                     └─► RedactionRegion(visionBoundingBox:)  coordinate flip
                                            └─► RedactionEngine.redactedImageData / redactedPDFData
                                                   └─► Data  (new file, no metadata)
                                                          └─► FileVault.write → DocumentStore.insert
```

The only types that cross module boundaries are `Data` and `Sendable` value types. `CGImage`,
`PDFDocument`, `NLTagger` and `NSRegularExpression` never leave the function body that created
them — that is how the whole pipeline satisfies Swift 6 complete strict concurrency without a
single `@unchecked Sendable` (`CLAUDE.md` rule 5).

## 3. Detection engine (F03 — the only `verified` feature)

### 3.1 Why checksums, not just regex

A bare `\d{12}` matches invoice totals and order IDs. On a real invoice that false-positive rate is
high enough that users stop reading the review screen and accept everything — which is precisely
how genuine PII gets missed. So every format that *has* a checksum is validated by one, and
confidence is assigned accordingly.

**The Verhoeff checksum** (`RedactApp/Core/Detection/Checksums.swift`) — this is the dihedral-group
D5 algorithm UIDAI uses for Aadhaar. It catches every single-digit error and every adjacent
transposition, which is exactly how OCR fails on a scanned card:

```swift
public enum Verhoeff {
    /// Multiplication table for the dihedral group D5.
    private static let d: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
        [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
        [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
        [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
        [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
        [6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
        [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
        [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
        [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
    ]

    /// Permutation table, applied with period 8 across the digit positions.
    private static let p: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
        [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
        [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
        [9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
        [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
        [2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
        [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
    ]

    /// Multiplicative inverse table for D5.
    private static let inverse: [Int] = [0, 4, 3, 2, 1, 5, 6, 7, 8, 9]

    /// True when `digits` (a digits-only string, check digit included) validates.
    public static func isValid(_ digits: String) -> Bool {
        guard !digits.isEmpty else { return false }
        var c = 0
        for (i, character) in digits.reversed().enumerated() {
            guard let value = character.wholeNumberValue, (0...9).contains(value) else {
                return false
            }
            c = d[c][p[i % 8][value]]
        }
        return c == 0
    }

    /// The check digit that would make `body` (payload without its check digit) valid.
    public static func checkDigit(for body: String) -> Int? {
        var c = 0
        for (i, character) in body.reversed().enumerated() {
            guard let value = character.wholeNumberValue, (0...9).contains(value) else {
                return nil
            }
            c = d[c][p[(i + 1) % 8][value]]
        }
        return inverse[c]
    }
}
```

`checkDigit(for:)` exists so the test suite can *mint* well-formed fake Aadhaar numbers instead of
hardcoding numbers nobody can re-derive — and so no real Aadhaar number ever enters the repo.

Also in that file: `isLuhnValid(_:)` (mod-10, every card network) and
`isGSTINChecksumValid(_:)` / `gstinCheckCharacter(forBody:)` (base-36, weights alternating 1,2 from
the left, each product folded as `quotient + remainder`, sum completed to a multiple of 36).

### 3.2 Rule table and confidence ladder

`PatternDetector.Rule.all` = `[gstin, aadhaar, creditCard, pan, ifsc, email, indianPhone,
internationalPhone, dateOfBirth]`. Each rule is `pattern` + optional payload capture group +
`confidence` + a `@Sendable` `validate` closure (the second stage).

| Kind | Confidence | Second stage |
|---|---|---|
| GSTIN | 0.99 | state code 1–38 **and** base-36 check character |
| Aadhaar | 0.99 | 12 digits **and** Verhoeff |
| Credit card | 0.98 | 13–19 digits **and** Luhn |
| Email | 0.97 | length ≤ 254 |
| Date of birth | 0.92 | label required; capture group 1 is redacted, not the label |
| PAN | 0.90 | shape only — no checksum exists |
| IFSC | 0.90 | shape only |
| Indian phone | 0.85 | shape only |
| International phone | 0.80 | 8–15 digits |
| Names / places / orgs | ≤ 0.75 | `NLTagger` hypothesis score, capped |

Three deliberate details worth copying:

- **Aadhaar's lookarounds** `(?<![0-9])(?<![0-9][ -])…(?![0-9])(?![ -][0-9])` stop the pattern
  latching onto the middle twelve digits of a grouped 16-digit card number.
- **Identifier patterns are case-sensitive uppercase.** PAN/GSTIN/IFSC are printed uppercase on
  every real document; matching case-insensitively turns ordinary words with trailing digits into
  false positives.
- **Dates need a label.** An unlabelled date is an invoice date far more often than a birth date,
  so the rule requires `DOB|Date of Birth|Birthdate|Born` and redacts the *value* via
  `capturesPayloadAtGroup: 1`.

Patterns are compiled **per call**, not cached in a `static let`: `NSRegularExpression` is not
`Sendable` and rule 5 forbids `@unchecked Sendable`. A dozen small compiles cost microseconds
against an OCR pass costing hundreds of milliseconds.

### 3.3 Overlap resolution

A GSTIN contains a PAN; a 12-digit Aadhaar looks like a long phone number. Redacting both is
visually harmless but produces a duplicated, contradictory review list, so
`DetectedPII.resolvingOverlaps` picks one winner per region: **checksum-proven kind → longer match
→ higher confidence → earlier position**, then re-sorts by document order.

### 3.4 Coordinate spaces — the bug class that would have shipped

Vision reports normalised boxes with a **bottom-left** origin. UIKit, Core Graphics contexts, and
SwiftUI use **top-left**. Drawing a Vision rect straight into a UIKit context puts the bar over the
wrong line of the page. In this product that is not cosmetic — it is a total failure of the one
promise.

The codebase makes the flip impossible to forget by putting it in exactly three places:

- `TextSpan.topLeftOriginBoundingBox` and `TextSpan.rect(in:)` (`Models.swift`)
- `RedactionRegion.init(visionBoundingBox:style:)` (`RedactionStyle.swift`)
- the `size.height - rect.maxY` flip inside `RedactionEngine.burnBars` (CG bottom-left origin)

`Tests/DetectionTests/ClassifierGeometryTests.swift` (13 tests) pins this, including that
`HeuristicClassifier.subBox` never returns a box *larger* than its parent line box.

### 3.5 The honest gap: `FoundationModelClassifier`

`ClassifierFactory.make()` returns `FoundationModelClassifier()` on iOS 26 — and that type
currently delegates 100% to `HeuristicClassifier`. It performs no LLM reasoning.

This is documented, not hidden: in the type's own doc comment, in F03's `notes` in
`feature_list.json`, and in [[gotcha-foundation-models-api-unconfirmed]]. The `FoundationModels`
API surface could not be confirmed while the file was written, and a plausible-looking invented API
that fails to compile would have broken the iOS 26 build for every other agent.

Before finishing it, three things must be confirmed: (1) the runtime availability query — `#available(iOS 26, *)`
is **not** sufficient, the model can be unavailable on supported OS versions; (2) whether
schema-constrained structured output exists; (3) per-page latency, which decides whether it runs
over the whole page or only over spans the heuristics were unsure about. Scope is **refinement, not
replacement** — no language model may un-flag a Verhoeff-valid Aadhaar.

## 4. Redaction core (F04 — the product claim)

### 4.1 The image path

```swift
public static func redactedImageData(
    from data: Data,
    regions: [RedactionRegion],
    format: RedactedImageFormat = .png
) throws -> Data {
    let decoded = try MetadataStripper.decodeImage(data)
    let upright = try bakeOrientation(decoded)
    let redacted = try burnBars(regions, into: upright)

    // Orientation is `.up` because it is now baked into the pixels. Writing the source tag here
    // would rotate the export a second time.
    return try MetadataStripper.encode(redacted, orientation: .up, format: format)
}
```

Four steps, each load-bearing:

1. **Decode to a raw pixel buffer.** Nothing from the source container carries forward.
2. **Bake EXIF orientation into the pixels** via Core Image's `.oriented(_:)`. Region coordinates
   come from what the user saw in the editor — the *oriented* image. Skip this and a bar over a
   phone number in a sideways photo lands on empty margin.
3. **Burn the bars** (below).
4. **Re-encode through the single writer**, which receives only a `CGImage` and an orientation tag.

The destruction itself:

```swift
private static func burnBars(_ regions: [RedactionRegion], into image: CGImage) throws -> CGImage {
    let size = CGSize(width: image.width, height: image.height)
    let context = try makeContext(size: size)
    context.draw(image, in: CGRect(origin: .zero, size: size))

    // `.copy` rather than the default `.normal`: normal blending would honour a source alpha,
    // and a bar that is 99% opaque still leaks the glyph underneath it. Copy overwrites.
    context.setBlendMode(.copy)

    for region in regions {
        guard region.style.securityLevel == .irreversible else {
            throw RedactionError.insecureStyleRejected
        }
        let rect = region.pixelRect(in: size)
        guard !rect.isEmpty else { continue }
        switch region.style {
        case .solidBar(let ink):
            let components = ink.sRGBComponents
            context.setFillColor(red: components.red, green: components.green,
                                 blue: components.blue, alpha: components.alpha)
        }
        // Flip to CoreGraphics' bottom-left origin. `RedactionRegion` is top-left by contract.
        context.fill(CGRect(x: rect.minX, y: size.height - rect.maxY,
                            width: rect.width, height: rect.height))
    }

    guard let result = context.makeImage() else { throw RedactionError.rasterisationFailed }
    return result
}
```

Supporting invariants:

- `RedactionBarInk.sRGBComponents` is **always alpha 1**, and alpha is not configurable. A
  translucent bar leaves the original luminance recoverable.
- `RedactionRegion.pixelRect(in:)` uses `.integral` — rounding **outward**. Rounding to nearest can
  leave a one-pixel sliver of a glyph at the bar edge, and a sliver of a digit narrows a guess.
- The `securityLevel` guard is unreachable today (one style case). It is a cheap tripwire so a
  future `.pixelate` cannot silently enter the destroy path.

### 4.2 Why `.pixelate` and `.blur` do not exist

`RedactionSecurityLevel` has two cases, and v1 ships only `.irreversible`. Pixelation and blur are
convolutions — deterministic functions *of* the original pixels, which are therefore still in the
output. For short strings from a known alphabet (which is exactly what PII is), an attacker renders
every candidate, applies the same filter, and matches. Offering them next to a solid bar in one
picker would imply equivalence. If they are ever added, they must be a separately labelled
"obscure (not secure)" action reporting `.reversible`.

### 4.3 The PDF path, and the tradeoff we accepted

**Every page carrying a redaction is rasterised in full and rebuilt as an image page.** That page
loses selectable text, copy-paste, reflow, and text-layer accessibility for *all* its content.

Alternatives, and why each was rejected:

| Alternative | Why rejected |
|---|---|
| `PDFAnnotation` black square | Drawn *above* the text object. `pdftotext`, text selection, or deleting the annotation recovers it. This is the failure that has leaked sealed court filings. It is a **control case** in our test suite that must leak. |
| Edit the content stream, delete covered glyphs | Requires resolving every font, encoding, and text-positioning operator correctly. Any operator mishandled leaves the glyph — and fails **silently**. |
| Rasterise only the region, splice into the stream | The original text object still sits in the stream underneath. |

Losing selectable text on a page is a visible, understandable cost. Leaving recoverable PII is an
invisible, catastrophic one. Pages with **no** regions are copied through untouched and keep their
text.

Rotation is handled: `thumbnail(of:for:)` honours page rotation, so for a page rotated 90/270 the
requested size is transposed (`abs(page.rotation) % 180 == 90`) or the render is squashed.

### 4.4 Known limitation — escalated, not fixed

`redactedPDFData` inserts region-free pages **verbatim**, keeping their content stream *and* any
annotations they already carried. If a user imports a PDF that another tool "redacted" by drawing
black `PDFAnnotation` squares on page 2 and redacts only page 1 here, the export ships page 2's
annotation intact — the recipient deletes it in Preview and reads the text underneath.

We never *create* that leak; we can *inherit* it. It is documented as an `- Important:` block on
the method (which previously framed pass-through purely as a text-preservation benefit) and in
[[pdf-passthrough-pages-keep-annotations]].

It was not fixed because the choice is a product decision, not a mechanical one:

- flatten everything → destroys the selectable text pass-through exists to preserve;
- strip annotations → silently discards legitimate comments, form values, signatures;
- warn at export → honest and lossless, but there is no export UI until Phase 2 (F09).

**Recommendation carried into Phase 2:** detect annotations on pass-through pages at export time
and offer "flatten these pages too" as an explicit user choice.

### 4.5 Metadata: rebuild, never edit

`MetadataStripper`'s whole strategy is to decode the pixels (or the page tree) and write a new file
from scratch, so metadata is dropped *by construction*. Deny-lists of keys go stale the moment an
SDK adds a dictionary; a rebuild cannot.

- Images: only the primary `CGImage` reaches `CGImageDestination`. EXIF, GPS, TIFF, IPTC, XMP,
  Photoshop/IRB, MakerNote and auxiliary images (thumbnails, depth, matte) are never carried
  forward. `kCGImagePropertyOrientation` is kept — it says nothing about the user, and dropping it
  would silently rotate the export.
- PDFs: `metadataFreeCopy(of:)` builds a **new** `PDFDocument`, moves the pages across, and clears
  `documentAttributes`. Clearing attributes in place would cover `/Info` but not the catalog's XMP
  packet, which survives re-serialisation of the same document object. Both PDF paths route through
  this one function so they cannot drift.

**The gotcha that cost the phase its first green gate:** ImageIO *synthesises* `{Exif}`
(ColorSpace, PixelXDimension, PixelYDimension) and `{TIFF}` (Orientation, resolution, compression)
on every write, regardless of the properties you pass — verified empirically by encoding a fresh
10×10 `CGImage` with only an orientation key. So a container-*name* assertion can never pass for
any encoder output. See [[imageio-synthesises-exif-tiff]]. The fix went in the assertion, not the
stripper: `identifyingMetadataKeys(in:)` reports offenders as `"{Dict}/Key"`, forbids `{GPS}`,
`{ExifAux}`, `{IPTC}`, `{XMP}`, `{Photoshop}`, `{MakerApple}` outright, and permits `{Exif}` /
`{TIFF}` **only** for the synthesised key set. That is stricter about real leaks, not weaker.

## 5. The irreversibility test — how the claim is proven

`Tests/RedactionTests/IrreversibilityTests.swift` (11 tests, 555 lines). It does **not** inspect our
own data structures — a bug in the engine would be a bug in that inspection too. It renders a known
secret, runs it through the real export path, and attacks the output the way an adversary would:
Vision OCR for images, `PDFDocument.string` (the `pdftotext` equivalent) for PDFs, ImageIO property
inspection for metadata.

The secret is `"ABCDE1234F"` — PAN-shaped, and distinctive enough that a partial OCR match is still
a failure.

### 5.1 The controls come first

Three tests exist purely to prove the harness can detect a broken engine:

```swift
/// If this fails, every "the secret is gone" assertion below is worthless, because the harness
/// cannot read the secret even when it is in plain sight.
func testOCRRecoversSecretFromUnredactedImage() throws { … }

/// The deliberately broken implementation: a bar composited at low alpha.
func testNaiveOverlayControlStillLeaksSecret() throws {
    let fixture = try ImageFixture(secret: secret)
    let naive = try fixture.overlaidWithoutDestroyingPixels(alpha: 0.12)
    let recognised = try Self.recognisedText(inImageData: naive)
    XCTAssertTrue(recognised.contains(secret), "…")
}

/// What Preview, Markup, and most "redaction" apps actually do.
func testPDFAnnotationControlStillLeaksSecret() throws {
    let source = try Self.makeTextPDF(secret: secret)
    let annotated = try Self.annotatedWithBlackSquare(source)
    let document = try XCTUnwrap(PDFDocument(data: annotated))
    XCTAssertTrue(document.string?.contains(secret) == true, "…")
}
```

A test harness that simply failed to read anything would report a clean pass for a completely
broken engine. These three make that impossible.

### 5.2 The assertion that is the product

```swift
func testRedactedImageIsUnrecoverableByOCR() throws {
    let fixture = try ImageFixture(secret: secret)

    let output = try RedactionEngine.redactedImageData(
        from: fixture.jpegData,
        regions: [RedactionRegion(rect: fixture.secretRegion)],
        format: .png
    )

    let recognised = try Self.recognisedText(inImageData: output)
    XCTAssertFalse(
        recognised.contains(secret),
        "OCR recovered the secret from redacted output. Recognised: \(recognised)"
    )

    // The label outside the region must survive — a redaction that destroys the whole page is
    // trivially "secure" and useless.
    XCTAssertTrue(
        recognised.contains("PERMANENT"),
        "Content outside the redaction region was destroyed. Recognised: \(recognised)"
    )
}
```

The OCR attack normalises whitespace so a reading of `"ABCDE 1234F"` still counts as a leak:

```swift
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false   // correction would "fix" the ID into a word
request.recognitionLanguages = ["en-US"]
request.minimumTextHeight = 0
…
return joined.filter { !$0.isWhitespace }
```

### 5.3 Constant-pixel test — proving it is not just a heavy blur

```swift
let samples = try Self.samplePixels(in: output, region: fixture.secretRegion, count: 64)
XCTAssertEqual(Set(samples).count, 1,
    "Redacted region contains \(Set(samples).count) distinct colours; it must be one constant.")
XCTAssertEqual(samples.first, Pixel(red: 0, green: 0, blue: 0, alpha: 255))
```

Samples are inset by 3px so they never straddle the bar edge, where antialiasing is legitimate. A
blur would leave varying pixels and be attackable offline; this asserts a single constant.

### 5.4 The rest

- `testRedactedPDFHasNoExtractableText` — `PDFDocument.string` must not merely lack the secret, it
  must be **empty** on the rasterised page; plus Title/Author/Subject/Creator/Keywords are `nil`,
  with a control asserting the fixture *had* a Title.
- `testRedactedPDFIsUnrecoverableByOCR` — renders the redacted page at 3× and OCRs the render.
- `testMetadataIsStrippedFromRedactedImage` / `testStandaloneMetadataStripRemovesEXIFAndGPS` —
  key-level assertions, with fixture controls proving the source really carried `{Exif}` and
  `{GPS}`.
- `testOnlyIrreversibleStylesExist` — fails if a future `.pixelate` is added without being marked
  `.reversible`, forcing the conversation.

Fixtures are **generated in code**, never loaded from disk, so the test cannot silently pass against
a stale asset. `ImageFixture` draws text with Core Text, records the drawn bounds, converts them to
a normalised top-left region, and encodes JPEG with real EXIF (`DateTimeOriginal`, `LensModel`),
GPS (12.9716 N, 77.5946 E) and TIFF (Make/Model) blocks attached.

**A fixture bug found and fixed during this phase:** `makeTextPDF` originally set
`kCGPDFContextTitle` through `beginPage(withBounds:pageInfo:)` — which is *page* info, never
surfaced by PDFKit as `documentAttributes`. `testPDFDocumentMetadataIsRemoved` was therefore
passing against a document that never had metadata. Moving it to
`UIGraphicsPDFRendererFormat.documentInfo` made a vacuous test meaningful. Vacuous tests are worse
than missing ones: they buy false confidence.

## 6. Persistence (F05)

- `RedactedDocument` (`@Model`) stores **no image bytes**. `thumbnailPath` and `pagePaths` are
  paths *relative to* `FileVault.root`. The app container UUID changes between installs and OS
  upgrades, so a persisted absolute path dangles — invisible until a user updates.
- `FileVault` lives in **Application Support**, not Documents (Documents is user-visible via
  Files.app and reserved for user-created content), is created with
  `FileProtectionType.completeUnlessOpen`, and is **excluded from backup** so a restored device
  cannot resurrect a document the user believed deleted.
- `url(forRelativePath:)` refuses any path that escapes the vault root rather than resolving it.
- `DocumentStore.delete(_:)` purges vault files **before** removing the record. Crash between the
  two leaves a record with missing files (recoverable, visible) rather than files no record points
  at (invisible — in a privacy app, an actual leak).
- `purgeOrphanedFiles()` sweeps at launch, because a crash between "file written" and "record
  saved" leaves an orphan.
- `DocumentStore` is `@MainActor` in full. `@Model` types are not `Sendable`; pinning the store to
  one actor is what makes them safe under strict concurrency with no `@unchecked`. Heavy work
  happens off-actor and returns `Data`.
- Sorting and pagination happen **in the store** (`FetchDescriptor.fetchLimit/fetchOffset`), not in
  memory — a library of hundreds of documents must not be fully faulted to draw a list.

`Tests/PersistenceTests/DocumentStoreTests.swift` (9 tests) covers round-trip, sort order, audit
append with denormalised count, **on-disk container teardown-and-reopen** (the literal "persists
across launch" criterion), delete-removes-vault-files, `deleteAll`, unknown-ID `.notFound`, orphan
sweep, and vault escape refusal. The relaunch test deliberately avoids
`PersistenceSchema.makeContainer(inMemory:)` — it hardcodes the store name, so two calls hit the
same file and tests would pollute each other. It builds `ModelConfiguration(schema:url:)` against a
per-test temp URL instead.

## 7. Design system (F02)

Two `CLAUDE.md` rules are unenforceable by review across parallel agents — rule 3 (no hardcoded
values) and rule 4 (reduceMotion honoured everywhere). One forgotten `withAnimation(.spring)` is a
silent accessibility regression `verify.sh` cannot catch. So both are expressed **as API**:

```swift
// Motion.swift — the guardrail. Every path returns crossFade when the setting is on,
// so the accessible path is also the shortest path to write.
public extension EnvironmentValues {
    var accessibleAnimation: @Sendable (Animation) -> Animation? {
        let reduceMotion = accessibilityReduceMotion
        return { reduceMotion ? Motion.crossFade : $0 }
    }
}

// Typography.swift — pinned DEC-002 point sizes AND Dynamic Type, together.
private struct TypeStyleModifier: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let style: Typography.Style

    init(_ style: Typography.Style) {
        self.style = style
        _scaledSize = ScaledMetric(wrappedValue: style.size, relativeTo: style.textStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(Typography.resolve(size: scaledSize, weight: style.weight, design: style.design))
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }
}
```

**Rejected alternative:** exposing plain `Font` constants. [[DEC-002-design-language]] pins point
sizes, and a bare `Font.system(size: 44)` ignores Dynamic Type entirely — it would have shipped an
accessibility failure by default. `@ScaledMetric(relativeTo:)` inside a `ViewModifier` is the only
mechanism that keeps the exact sizes *and* scales them, which is why `.typeStyle(_:)` is a modifier
rather than a constant.

Tokens (`Tokens.swift`) are law: `BG.base #0A0E1A`, `BG.card #131A2E`, `Accent.violet #A855F7`,
`Accent.amber #FF6B3D`, `Text.primary #EDF1FA`, radii 20/13/9, spacing 6/12/20/32/48,
`Size.minimumHitTarget = 44`. `Tests/DesignSystemTests.swift` pins the accent hexes and the spacing
scale so a "tidy-up" cannot drift them.

`TokenGallery.swift` renders every token, surface and component on one page, with a second preview
at `.accessibility5` Dynamic Type. It is reachable at runtime behind `#if DEBUG` from `RootView`
(compiled out of Release, so rule 10 is untouched) — a preview-only gallery cannot be checked by
the simulator run in `verify.sh`.

Known gaps: Space Grotesk / Inter are **not bundled** — `Typography.resolve` returns `.system`
with `.rounded` for display and `.default` for body. [[DEC-004-no-network]] forbids fetching them,
so this is a stand-in with a one-line swap point. Contrast is unmeasured;
`Token.Text.faint (#5A6782)` on `Token.BG.base (#0A0E1A)` is the likely 4.5:1 failure and is used
only for decorative captions.

## 8. Commands — real input, real output

Session bootstrap:

```bash
$ ./init.sh
REDACT — Shipaton 2026
on-device PII redaction for iOS

  19 days until App Store submission target (2026-09-05)
  44 days until Shipaton closes (2026-09-30)
…
Read before working
  1. CLAUDE.md        the ten rules
  2. docs/memory.md   current state
  3. AGENTS.md        your scope allowlist
```

Regenerate the project after adding or removing any source file (the `.pbxproj` is generated from
`project.yml`, never hand-edited — that is what lets parallel agents add files without merge
conflicts):

```bash
$ xcodegen generate
Created project at /Users/.../RedactApp.xcodeproj
```

Build and test:

```bash
$ xcodebuild -project RedactApp.xcodeproj -scheme RedactApp \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
Executed 79 tests, with 0 failures (0 unexpected) in 4.348 seconds
** TEST SUCCEEDED **
```

The gate:

```bash
$ ./verify.sh
  ✓ no key material tracked
  ✓ no networking outside RevenueCat
  ✓ no placeholder strings in user-facing code
  ✓ build succeeded
  ✓ tests passed
  ✓ session log exists for 2026-08-17
  ✓ memory index rebuilt
━━━ GATE PASSED ━━━
```

Memory:

```bash
$ python3 tools/memory_index.py build
$ python3 tools/memory_index.py query "design system tokens typography glass surfaces motion"
1. Architecture at a glance  [docs/memory.md:52]  score=16.01
2. Decision  [docs/memory/decisions/DEC-002-design-language.md:4]  score=5.87
3. Why  [docs/memory/decisions/DEC-002-design-language.md:12]  score=4.80
4. [17:00] orchestrator — Xcode project scaffolded, builds and runs (F01)  score=3.86
```

Driving the simulator directly (the iOS Simulator MCP is blocked by `xcode-select` — see
[[gotcha-xcode-select]]; the fix needs a human password):

```bash
$ xcrun simctl boot "iPhone 17 Pro"
$ xcrun simctl install "iPhone 17 Pro" <path>/RedactApp.app
$ xcrun simctl launch "iPhone 17 Pro" com.senthilnathanraja.redact
$ xcrun simctl io "iPhone 17 Pro" screenshot out.png
```

To run one suite only:

```bash
$ xcodebuild -project RedactApp.xcodeproj -scheme RedactApp \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:RedactAppTests/IrreversibilityTests test
```

Test inventory (79 total): PatternDetector 16 · ClassifierGeometry 13 · Checksum 11 ·
FalsePositive 11 · Irreversibility 11 · DocumentStore 9 · NameDetector 6 · DesignSystem 2.

## 9. Failure modes

| Failure | Symptom | Where it is caught |
|---|---|---|
| Vision box drawn without the origin flip | Bar lands on the wrong line; export looks clean, leaks | `ClassifierGeometryTests`; the flip is centralised in three functions |
| EXIF orientation not baked | Bar on empty margin in a sideways photo | `bakeOrientation` before `burnBars`; visually checkable in the editor |
| `.normal` blend instead of `.copy` | 99%-opaque bar still leaks the glyph | `testRedactedPixelsAreAConstant` |
| Rounding pixel rect to nearest | One-pixel sliver of a digit survives | `pixelRect(in:)` uses `.integral` (outward) |
| A future `.pixelate` style added | Reversible treatment enters the destroy path | `insecureStyleRejected` guard + `testOnlyIrreversibleStylesExist` |
| PDF annotation instead of raster | `pdftotext` recovers everything | `testPDFAnnotationControlStillLeaksSecret` (control) + `testRedactedPDFHasNoExtractableText` |
| **Inherited annotation on a pass-through page** | Recipient deletes the box in Preview | **Not caught. Open.** [[pdf-passthrough-pages-keep-annotations]] |
| Metadata assertion on container names | Test can never pass; masks whether stripping works | [[imageio-synthesises-exif-tiff]]; now key-level |
| Absolute path persisted | Dangling file after an app update | `FileVault` stores relative paths only; `DocumentStoreTests` relaunch test |
| Orphaned vault file after a crash | Redacted content survives a "delete" | `purgeOrphanedFiles()` at launch |
| Regex without checksum | Invoice totals blacked out; users stop reading the review list | `FalsePositiveTests` (11) |
| OCR language correction on | An ID gets "corrected" into a word, defeating the checksum | `usesLanguageCorrection = false` by default |
| Two source files with the same basename | Xcode target rejects the build | Hit for real: `Core/Persistence/Models.swift` → `PersistenceModels.swift` |

## 10. What is incomplete — read this before trusting the phase

1. **F02, F04, F05 are `built`, not `verified`.** The fixer applied the verifier's findings and may
   not verify its own work (`CLAUDE.md` rule 7). **The immediate next action for Phase 1 is an
   independent verifier pass over F02/F04/F05 now that the gate is green.** Only F03 is `verified`.
2. **Pass-through PDF pages keep inherited annotations.** Open, escalated to the human, awaiting a
   product decision in Phase 2 (F09 export). See §4.4.
3. **`FoundationModelClassifier` does no LLM reasoning.** Delegates to the heuristic path. See §3.5.
4. **Fonts are not bundled.** Typography falls back to system faces.
5. **Contrast is not measured.** `Token.Text.faint` on `Token.BG.base` is the suspected failure.
6. **Reduce-motion has no preview.** SwiftUI exposes `accessibilityReduceMotion` read-only; it must
   be checked in the simulator under Settings → Accessibility → Motion.
7. **The simulator MCP is blocked** by `xcode-select` pointing at the Command Line Tools. `simctl`
   is a sufficient workaround for install/launch/screenshot, but interactive flows in Phase 2 will
   want the live panel. Fix needs a human: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
8. **Gate status caveat.** The last recorded full run is **79 tests, 0 failures, `verify.sh` exit 0**
   (fixer, 17:36). The phase-close run summary flagged the test check as not passing. These
   disagree, and this document will not pretend otherwise: **re-run `./verify.sh` and trust its
   output over both.** The build succeeding is not in dispute.
9. No feature UI exists yet. Detection, redaction, and persistence have no screen driving them —
   that is Phase 2 (F06–F09, F11).

## 11. How to replicate this phase from scratch

1. `./init.sh` — read `CLAUDE.md`, then `docs/memory.md`, then `AGENTS.md`.
2. Declare the four builder scopes as disjoint allowlists; run them in parallel. Each writes its
   memory entry *as it works*, not at the end.
3. Write `project.yml`, never the `.pbxproj`. Run `xcodegen generate` after any file add/remove.
4. Build the redaction test **before or alongside** the engine, and write the failing controls
   first — the naive overlay and the PDF annotation. If they do not leak, nothing else means
   anything.
5. Integrate: `xcodegen generate && xcodebuild … test`. Expect exactly one class of mechanical
   collision (duplicate basenames).
6. One verifier pass, read-only, fresh context. One fixer pass. Anything unresolved →
   `docs/memory/gotchas/` + escalate. No third cycle ([[DEC-005-bounded-loop]]).
7. Write the triad, update `docs/memory.md`, `python3 tools/memory_index.py build`.

**Related:** [[DEC-001-app-concept]] · [[DEC-002-design-language]] · [[DEC-003-ios-target]] ·
[[DEC-004-no-network]] · [[DEC-005-bounded-loop]] · [[2026-08-17-01]] ·
[[phase-1-non-technical]] · [[phase-1-guide-for-kids]]
