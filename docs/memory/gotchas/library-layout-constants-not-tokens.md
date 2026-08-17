---
id: library-layout-constants-not-tokens
date: 2026-08-17
phase: 2
tags: [gotcha, library, design-system, tokens, scope]
status: open
---

# Four library measurements live outside `DesignSystem/`

## What

`RedactApp/Features/Library/LibraryLayout.swift` declares:

| Constant | Value | What it is |
|---|---|---|
| `pageAspectRatio` | `1/√2` | ISO 216 page proportion for the thumbnail box |
| `rowThumbnailWidth` | `Token.Size.iconWell * 1.5` | row thumbnail width (derived from a token) |
| `rowThumbnailPixels` | `240` | max pixel edge requested from ImageIO for a row |
| `detailPreviewPixels` | `2048` | max pixel edge for the detail preview |
| `undoWindow` | `5s` | how long a staged delete can be taken back |

`CLAUDE.md` rule 3 says a missing token is added to `DesignSystem/` **first**. That could
not be done here: `DesignSystem/**` is the `design-system` agent's allowlist and editing it
would have collided with a parallel builder (rule 8).

## Why this is not simply a rule-3 violation

Everything rule 3 actually names — colour, font, radius, spacing, shadow, animation curve —
comes from `Token`/`Typography`/`Motion` throughout this feature. What is left are two
*decode budgets* (pixel counts handed to ImageIO, not layout), one *duration*, and one
*proportion* taken from a paper standard. None of them has a token today.

They are named in one enum rather than spelled inline in the views, so promoting them is a
find-and-replace of five symbols, not an archaeology exercise.

## The fix

When `DesignSystem/**` reopens, move `pageAspectRatio` and `rowThumbnailWidth` into
`Token.Size`, and `undoWindow` into `Motion.Duration`. The two pixel budgets probably
belong in a `Token.Image` group, since the export and editor screens will want the same
numbers rather than picking their own.

**Related:** [[DEC-002-design-language]]
