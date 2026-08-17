# Pass-through PDF pages keep inherited annotations

**Status:** open — documented, not fixed. Escalated to human 2026-08-17.

## What

`RedactionEngine.redactedPDFData` rasterises any page that carries a redaction region, which
destroys text objects and annotations on that page. Pages with **no** regions are inserted
verbatim (`output.insert(page, at:)`) to preserve their selectable text. Those pages keep their
original content stream *and* any annotations they already had.

## Why it matters

If a user imports a PDF that a previous tool "redacted" by drawing black `PDFAnnotation` squares
on page 2, and then uses Redact on page 1 only, the export ships page 2's annotation intact. The
recipient deletes it in Preview and reads the text underneath. This is exactly the leak class
`IrreversibilityTests.testPDFAnnotationControlStillLeaksSecret` exists to demonstrate — we simply
do not create it ourselves, we can inherit it.

## Why it was not fixed in this pass

The fix is a product decision, not a mechanical one, and each option has a real cost:

- **Flatten every page** — destroys selectable text on pages the user never touched, which is the
  entire reason pass-through exists.
- **Strip annotations from pass-through pages** — silently discards legitimate annotations
  (comments, form values, signatures) the user may want to keep.
- **Warn in the export UI** — honest and lossless, but there is no export UI yet (Phase 2, F09).

## What was done instead

The limitation is documented on `redactedPDFData`'s doc comment as an `- Important:` block, in the
engine's own words, so nobody reads the pass-through as unconditionally safe.

## Next step

Decide the policy when the export UI lands in Phase 2. Recommended: detect annotations on
pass-through pages at export time and offer "flatten these pages too" as an explicit choice, so the
user trades text selection for safety knowingly.
