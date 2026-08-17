---
id: DEC-002-design-language
date: 2026-08-17
phase: 0
tags: [decision, design, tokens]
status: accepted
---

# DEC-002 — Design language ported from the DIVS executive-overview HTML

## Decision

The app's visual language is a native SwiftUI translation of the user's existing HTML deck
(`~/Downloads/divs-team-index2 (2).html`): **dark navy base, violet→amber gradient accent, glass
surfaces, Space Grotesk display type, ambient glow.**

This is the source of truth. `DesignSystem/` implements exactly these values and nothing else.

## Why

- Visual continuity with the user's existing work — the app looks like it belongs to them
- Dark + gradient + glass reads as premium, which is what the **RevenueCat Design Award** rewards
- A privacy/security product benefits from a serious, technical aesthetic rather than a playful one

## Extracted tokens — these are law (`CLAUDE.md` rule 3)

### Colour

| Token | Hex | Role |
|---|---|---|
| `bg0` | `#0A0E1A` | app background, deepest |
| `bg1` | `#0E1424` | section background |
| `bg2` | `#131A2E` | card surface |
| `bg3` | `#1A2340` | card surface, raised/hover |
| `accentViolet` | `#A855F7` | primary accent (gradient start) |
| `accentVioletLight` | `#C084FC` | accent, lighter |
| `accentAmber` | `#FF6B3D` | secondary accent (gradient end) |
| `accentAmberLight` | `#FF8C5A` | accent, lighter |
| `cyan` | `#22D3EE` | rare highlight only |
| `textPrimary` | `#EDF1FA` | body text |
| `textMuted` | `#93A0BF` | secondary text |
| `textFaint` | `#5A6782` | tertiary / disabled |
| `hairline` | white @ 7% | borders |
| `hairlineStrong` | white @ 12% | emphasised borders |

**Primary gradient:** `linear-gradient(135°, #A855F7 → #FF6B3D)` — in SwiftUI, `LinearGradient`
from `.topLeading` to `.bottomTrailing`.

**Soft gradient** (icon wells, inactive fills): the same two stops at 16% opacity.

### Type

- Display: **Space Grotesk** — 400/500/600/700. Headings, numerals, brand.
- Body: **Inter** — 300/400/500/600.
- Both must be **bundled in the app**, not fetched. Remote fonts would violate [[DEC-004-no-network]].
- Display tracking is tight: `-0.02em` to `-0.03em` at large sizes. Body line-height 1.6–1.7.

### Shape and depth

- Card radius **18–20pt**; small elements 12–13pt; pills fully rounded
- Shadow: `0 24px 60px -24px rgba(0,0,0,0.7)` — deep, soft, low-opacity
- Accent glow on hover/active: `0 30px 60px -26px rgba(168,85,247,0.55)`
- Glass: `.ultraThinMaterial` over `bg2`, with a **gradient hairline border**
  (`.strokeBorder(LinearGradient(...), lineWidth: 1)`) — the HTML achieves this with a
  mask-composite trick; SwiftUI does it natively

### Motion

The HTML's signature easing is `cubic-bezier(.2, .8, .2, 1)` — fast out, gentle settle.
SwiftUI equivalent: **`.spring(response: 0.45, dampingFraction: 0.8)`**. Use it as the default.

- Ambient background drift: 16s, ease-in-out, alternating — slow enough to feel alive, not distracting
- Hover/press lift: `translateY(-6pt)` + shadow bloom
- Progress/meter fills animate over ~1.1s with a one-shot light sheen sweep

**Every animation must check `@Environment(\.accessibilityReduceMotion)` and degrade to a
cross-fade.** Not optional — see `CLAUDE.md` rule 4.

## The signature moment

The redaction animation is the screenshot that wins or loses the Design Award: a scanline sweeps the
document revealing detected PII spans one by one, then the redaction bars slam in with a haptic.
Budget real time for it. It is the app's single most memorable frame and belongs in the App Store
screenshots and the demo video.

## Constraint

Dark-only for v1. A light theme doubles the token surface and the QA matrix for no award benefit.
Revisit after submission.

**Related:** [[DEC-001-app-concept]] · [[DEC-004-no-network]]
