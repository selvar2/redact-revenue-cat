---
id: gotcha-foundation-models-api-unconfirmed
date: 2026-08-17
phase: 1
tags: [gotcha, ios26, foundation-models, detection]
status: open
---

# `FoundationModelClassifier` is a documented stub, not a Foundation Models integration

## What

`RedactApp/Core/Detection/PIIClassifier.swift` defines

```swift
@available(iOS 26, *)
public struct FoundationModelClassifier: PIIClassifier {
    public func classify(_ candidates: [TextSpan]) async throws -> [ClassifiedSpan] {
        try await heuristic.classify(candidates)
    }
}
```

It conforms to the protocol and `ClassifierFactory.make()` selects it on iOS 26, but it performs
**no LLM reasoning**. It returns exactly the ``HeuristicClassifier`` result.

## Why it was left this way

DEC-003 reserves this path for Apple's on-device `FoundationModels` framework. While writing the
detection engine I could not confirm the framework's real API surface — the session type, the
prompt/response shape, availability checking, and the guided-generation schema types — from
documentation available to me.

Writing a plausible-looking API that does not compile would have been strictly worse than an
honest gap: the detection module is a dependency of the Scan and Editor features, so a
non-compiling iOS 26 branch would break every other agent's build, and it would have to be
rewritten from scratch once the real API was known. A stub that compiles, is selected, and
returns correct (if unimproved) results costs nothing and blocks nobody.

There is one accidental benefit: because both paths return identical values today, the iOS 17
fallback is exercised on every device, which is the property DEC-003 asks the verifier to check.

## What must be confirmed before this is finished

1. The `FoundationModels` module name, the session/request type, and how availability is queried
   at runtime (the model may be unavailable even on iOS 26 — device class, storage, Apple
   Intelligence opt-in). **The `#available(iOS 26, *)` check is not sufficient on its own**; a
   runtime availability check plus a fallback to `HeuristicClassifier` is required, or the
   feature breaks on unsupported iOS 26 hardware.
2. Whether structured output (a schema-constrained response) is available, so spans come back as
   typed classifications rather than text to be parsed.
3. Latency on a full page. If the model cannot classify a page's ambiguous spans in well under a
   second, it should run only over the spans the heuristics were unsure about, not the whole page.

## Scope note

The intended use is **refinement, not replacement**. The checksum layer must stay authoritative:
a Verhoeff-valid Aadhaar is proven, and no language model may be allowed to un-flag it. The LLM's
job is the ambiguous middle — is "Salem" a city or a surname, is this number an account or an
invoice total, is this a home address or a company's registered office.

**Related:** [[DEC-003-ios-target]]
