---
id: manual-region-resize-undo
date: 2026-08-17
phase: 2
tags: [gotcha, editor, undo, scope]
status: open
---

# Resizing a hand-drawn box costs two undos

## What happens

In the editor, dragging a corner handle of a manual redaction box (or using its VoiceOver
adjustable action) commits through `EditorView.resize(_:to:contentSize:)`, which does:

```swift
session.removeManualRegion(id: manual.id)
let replacement = session.addManualRegion(region, onPage: manual.pageIndex)
```

`RedactionSession.mutate` records one undo entry per call, so a single resize pushes **two**
entries. Undo once and the box vanishes; undo twice and the original size returns. The box also
gets a new `UUID`, so anything holding the old id (only the editor's `selectedManualID`, which is
re-pointed immediately) would go stale.

## Why it was left this way

The shared contract for `RedactionSession` exposes `addManualRegion` and `removeManualRegion` and
no in-place update. `RedactApp/Features/Shared/**` is not in `feature-editor`'s allowlist
(`AGENTS.md`), and `agent.md` is explicit: do not make the out-of-scope change, log it, continue.
Every alternative inside scope is worse — keeping resize purely local would silently lose the edit,
and dropping resize entirely would leave a handle-less box that can only be deleted and redrawn.

## The fix

Add to `RedactionSession`, in the `Editing` section, alongside the other funnelled mutations:

```swift
public func updateManualRegion(id: ManualRegion.ID, to region: RedactionRegion) {
    mutate { state in
        guard let index = state.manualRegions.firstIndex(where: { $0.id == id }) else { return }
        state.manualRegions[index].region = region
    }
}
```

`ManualRegion.region` is already `var`, so this needs no other change. Then in `EditorView.resize`,
replace the remove/add pair with a single `session.updateManualRegion(id: manual.id, to: region)`
and delete the `selectedManualID` re-pointing.

Owner: whichever agent holds `RedactApp/Features/Shared/**` (the Phase 2 contract author).

**Related:** [[2026-08-17-01]] [[DEC-002-design-language]]
