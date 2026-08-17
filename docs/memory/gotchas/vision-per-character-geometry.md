# Gotcha: Vision per-character geometry — two traps, both silent

**Status:** resolved in code (2026-08-17, fixer pass, Phase 2). Read before touching
`TextRecogniser.characterBoxes(of:within:)` or `TextSpan.measuredBox(forLocalRange:)`.

## 1. Never split an OCR line box by character count

`VNRecognizeTextRequest` returns **one box per line**. Phase 2 derived sub-line geometry by
interpolating that box on character index (`fractionStart = start / unitCount`). That is only
correct for a monospaced face. On the proportional type every real document uses, the projected box
drifts, and `RedactionRegion(detected:)`'s 0.004 padding (~8px on a 2000px page) does not absorb it.

Measured on the bundled sample, exported from the running app: the bar over `14/03/1994` started one
glyph late and the file rendered **`Date of Birth: 1`**; the bar over `ZZZZ0123456` rendered
**`IFSC: Z`**. A leading digit of a date of birth cuts a guess from thousands of candidates to dozens.

The fix: `VNRecognizedText.boundingBox(for: Range<String.Index>)` reports the real quad for a
substring. `TextRecogniser` now measures every character once at recognition time and carries the
result in `TextSpan.characterBoxes`; `HeuristicClassifier` prefers it and falls back to `subBox`
only when there are no measurements.

## 2. Never ask Vision for the box of a whitespace character

Asked for the box of a lone space, `boundingBox(for:)` **does not throw** — it returns a quad
spanning a large part of the page. Unioned into a detection's geometry, that produced a bar over the
entire top half of the payslip. Every identifier on the sample contains a space, so this was the
common case, not an edge case. It was caught only by looking at the exported pixels; every
text-level test passed on that image.

`characterBoxes(of:within:)` therefore skips whitespace entirely and rejects any box that does not
sit inside its own line's box. A space between two measured glyphs is covered by the union of its
neighbours, so nothing is lost.

## Why the test suite could not see either failure

`ClassifierGeometryTests` asserted `subBox` was monotonic and contained by its parent — properties
the broken code satisfied perfectly. `IrreversibilityTests` hands the engine regions it invents
itself, so it never crosses the detector→region seam. The gate was green over an output that leaked.

Worse, **OCR alone is not a sufficient oracle for this class of bug**: Vision discards a lone glyph
stranded against a black bar, so an export that visibly reads `Date of Birth: 1` is reported by
Vision as `Date of Birth:`. The first version of the new end-to-end test passed on the broken build
for exactly this reason.

`Tests/RedactionTests/SampleDocumentLeakTests.swift` now uses **pixels** as the oracle:
`testEveryPixelOfASecretIsCoveredInTheExport` takes Vision's own per-character measurement of the
source line as ground truth and asserts the export is one flat colour across that footprint. Verified
to fail loudly on the old geometry (5 detections, up to 8 distinct colours inside a secret's
footprint) and pass on the new.
