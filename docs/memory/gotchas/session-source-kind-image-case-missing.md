---
id: session-source-kind-image-case-missing
date: 2026-08-17
phase: 2
tags: [gotcha, compile-error, scope-violation-avoided, shared-contract]
status: open
---

# `SessionSource.kind` returns `DocumentSourceKind.image`, which does not exist

## What

`RedactApp/Features/Shared/RedactionSession.swift:34-39`:

```swift
public var kind: DocumentSourceKind {
    switch self {
    case .image: return .image   // ← DocumentSourceKind has no `.image`
    case .pdf:   return .pdf
    }
}
```

`DocumentSourceKind` (`RedactApp/Core/Persistence/PersistenceModels.swift:6-10`) is:

```swift
public enum DocumentSourceKind: String, Codable, Sendable, CaseIterable {
    case photo
    case scan
    case pdf
}
```

There is no `.image` case, so this is a hard compile error in the shared contract file. It will
fail the first `xcodebuild` of Phase 2 for every feature agent at once, not just for Scan.

## Why it is not fixed here

`RedactApp/Features/Shared/**` is not on the `feature-scan` allowlist in `AGENTS.md`. Per `agent.md`,
an out-of-scope edit is a defect even when it is obviously correct, because parallel agents are
writing the same tree.

## The fix, for whoever owns Shared

`.image` is genuinely ambiguous: a `SessionSource.image(Data)` can come from the photo library
(`.photo`) or from a VisionKit capture (`.scan`), and the enum cannot tell them apart. So mapping it
to a single case throws away information the Library needs for its row icons. Two options:

1. **Cheap:** `case .image: return .photo`. Compiles, but a camera scan is filed as a photo.
2. **Correct:** give `SessionSource` the origin it already implicitly has —
   `case image(Data, origin: DocumentSourceKind)` or a separate `origin` field on
   `RedactionSession` — and let `kind` return it.

Option 2 is preferable. Scan already knows the origin at import time (camera vs Photos vs Files) and
would pass it in for free.

## What Scan did instead

`ImportPipeline` declares its own `ImportPipeline.Origin` (`camera` / `photoLibrary` / `files`) and
uses it for default document titles, so no Scan code reads `SessionSource.kind`. When Shared is
fixed, `Origin` can map onto `DocumentSourceKind` in one function.

**Related:** [[phase-1-technical]]
