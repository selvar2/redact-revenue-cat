---
id: session-source-kind-image-vs-photo
date: 2026-08-17
phase: 2
tags: [gotcha, build-break, persistence, shared-contract]
status: open
raised-by: onboarding
---

# `SessionSource.kind` returns `.image`, which `DocumentSourceKind` does not have

## The break

`RedactApp/Features/Shared/RedactionSession.swift:36`

```swift
public var kind: DocumentSourceKind {
    switch self {
    case .image: return .image   // ← no such case
    case .pdf:   return .pdf
    }
}
```

`RedactApp/Core/Persistence/PersistenceModels.swift:6`

```swift
public enum DocumentSourceKind: String, Codable, Sendable, CaseIterable {
    case photo
    case scan
    case pdf
}
```

Whole-module typecheck, iOS 17 simulator SDK, `-swift-version 6 -strict-concurrency=complete`:

```
Features/Shared/RedactionSession.swift:36:30: error: type 'DocumentSourceKind' has no member 'image'
```

This is currently the **only** compile error outside files that were mid-write, so it blocks the
whole target.

## Why I did not fix it

Both files are outside the `onboarding` allowlist (`Features/Shared/**` belongs to whoever owns the
Phase 2 shared contract; `Core/Persistence/**` belongs to `persistence`). `AGENTS.md`: editing
outside the allowlist is a defect, not initiative.

## The fix, for whoever owns it

Change the mapping, not the enum. `DocumentSourceKind`'s raw values are persisted, so adding
`case image` would leave three near-synonyms (`photo`, `scan`, `image`) in a store that can never
drop one.

`SessionSource` cannot tell a camera scan from a picked photo — that distinction is made by
`ImportPipeline` in Scan, which knows which entry point produced the bytes. So either:

1. `case .image: return .photo` in `SessionSource.kind`, and let Scan overwrite the value to
   `.scan` when the source came from VisionKit; or
2. give `SessionSource.image` an associated origin so the mapping is total.

Option 1 is the smaller change and matches how Scan is already structured.

**Related:** [[phase-1-technical]] [[memory-index]]
