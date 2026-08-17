---
id: DEC-001-app-concept
date: 2026-08-17
phase: 0
tags: [decision, product, app-review]
status: accepted
---

# DEC-001 — Build "Redact", an on-device PII scrubber

## Decision

Build **Redact**: scan or import a document, detect personal information, destroy it irreversibly,
export. 100% on-device.

## Context

Shipaton imposes no theme — any app category is allowed. The real constraints were: solo developer,
~4 weeks of build time before a 2026-09-05 submission target, no backend to operate, no budget for
API inference, and it must survive App Review on the first or second attempt.

## Alternatives rejected

| Option | Why rejected |
|---|---|
| AI chatbot / LLM wrapper | Guideline 4.3 (spam) rejection is near-certain; also costs money per token |
| Habit / mood / streak tracker | Textbook Guideline 4.2 "minimum functionality" rejection |
| Anything with user-generated content | Triggers Guideline 1.2 — owes moderation, reporting, blocking. Weeks of unrelated work |
| Receipt/expense scanner | Good, but crowded. Kept as the fallback concept |

## Why Redact wins on every constraint

- **Guideline 4.2**: unambiguous utility with a clear purpose — the safest category with App Review
- **Guideline 1.2**: no UGC, no social surface, no moderation obligation
- **Cost**: Apple's on-device frameworks are free. Zero marginal cost per user, forever
- **Privacy**: on-device processing lets us answer "No Data Collected" truthfully — see [[DEC-004-no-network]]
- **Differentiation**: the category is genuinely under-served, and almost every competitor is *wrong*
  (see below), which is a real product claim rather than marketing
- **Audience fit**: an enterprise data-privacy framing demos well to a corporate audience, which was
  an explicit goal

## The core insight that makes it a real product

Drawing a black rectangle over text in a PDF is **not** redaction. The text object survives underneath;
`pdftotext` recovers it in one command. This has caused real leaks at courts, governments, and law
firms. Most users assume Markup's black box is safe. It isn't.

Doing it *correctly* — destroying the underlying content, stripping metadata, flattening the output —
is the product. It is also testable, which is why the irreversibility test is a hard requirement in
[[CLAUDE.md]] rule 2.

## Consequences

- We must prove irreversibility with a test that OCRs our own output (F04 acceptance criterion)
- Metadata stripping is in scope from day one, not a later feature — a photo of a redacted document
  still carries GPS coordinates otherwise
- Free/paid split falls out naturally: volume and format, not crippled core function

**Related:** [[DEC-002-design-language]] · [[DEC-003-ios-target]] · [[DEC-004-no-network]]
