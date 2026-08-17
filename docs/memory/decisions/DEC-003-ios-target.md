---
id: DEC-003-ios-target
date: 2026-08-17
phase: 0
tags: [decision, architecture, ai]
status: accepted
---

# DEC-003 — iOS 17 floor, iOS 26 Foundation Models as a gated enhancement

## Decision

Deployment target **iOS 17.0**. Apple's on-device LLM (`FoundationModels`, iOS 26+) is used when
available and cleanly absent when not.

Structured as one protocol, two implementations — a strategy swap, **not** a forked UI:

```swift
protocol PIIClassifier: Sendable {
    func classify(_ candidates: [TextSpan]) async throws -> [ClassifiedSpan]
}

// iOS 17+ — always available. Regex + NLTagger NER.
struct HeuristicClassifier: PIIClassifier { … }

// iOS 26+ — on-device LLM for ambiguous spans and document-type inference.
@available(iOS 26, *)
struct FoundationModelClassifier: PIIClassifier { … }

enum ClassifierFactory {
    static func make() -> any PIIClassifier {
        if #available(iOS 26, *) { return FoundationModelClassifier() }
        return HeuristicClassifier()
    }
}
```

## Why not iOS 26-only

Foundation Models gives a genuinely better "AI-powered" story and better handling of ambiguous cases
("is *Salem* a city or a surname?"). But an iOS 26 floor cuts the install base hard for no judging
benefit — Shipaton judges the app, not its minimum OS.

## Why not iOS 17-only

Deterministic regex + `NLTagger` covers structured IDs (PAN, Aadhaar, IFSC, GSTIN, card, email,
phone) very well, and named entities acceptably. What it cannot do is reason about context. The LLM
path is a real quality lift on messy documents, and it is free and on-device — no reason to skip it.

## The rule that keeps this cheap

**iOS 17 must be fully functional — degraded intelligence, never a broken feature.** No screen,
button, or flow may exist only on iOS 26. The difference is detection quality, invisible in the UI.

This is what keeps the fallback to roughly one extra day rather than a second codebase. If a feature
starts to require branching UI, the answer is to drop it, not to fork.

## Verification

The verifier explicitly checks: does the app build and run correctly with the iOS 26 path forced
off? A fallback that is never exercised is a fallback that does not work.

**Related:** [[DEC-001-app-concept]] · [[DEC-004-no-network]]
