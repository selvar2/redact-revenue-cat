# `SessionSource.kind` maps to a `DocumentSourceKind` case that does not exist

**Status:** open — found 2026-08-17 by `feature-export` (F08). Out of that agent's allowlist
(`RedactApp/Features/Shared/**` belongs to whoever built the Phase 2 shared contract), so it was
**not** fixed. Escalated.

## What

`RedactApp/Features/Shared/RedactionSession.swift`:

```swift
public var kind: DocumentSourceKind {
    switch self {
    case .image: return .image   // ← no such case
    case .pdf:   return .pdf
    }
}
```

`DocumentSourceKind` is declared in `RedactApp/Core/Persistence/PersistenceModels.swift` with
exactly three cases: `photo`, `scan`, `pdf`. There is no `image`.

## Why it matters

This is a hard compile error in the app target, so **nothing in Phase 2 builds** until it is fixed.
It is invisible to `swiftc -parse` (which is all any builder agent was permitted to run), which is
why it survived into four parallel feature agents' assumptions.

## Fix

One line, in the file's owner's scope: `case .image: return .photo`.

`.photo` is the right value rather than adding an `.image` case — the raw value `"photo"` is already
persisted by `RedactedDocument.sourceKindRaw`, and `PersistenceModels.swift` states that existing
raw values must never change.

## Workaround in place

`ExportPipeline.run` does not call `SessionSource.kind`. It maps `source.isPDF ? .pdf : .photo`
directly, so export does not depend on the broken property. Other features may not have.
