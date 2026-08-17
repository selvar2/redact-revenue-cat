---
id: library-pro-access-seam
date: 2026-08-17
phase: 2
tags: [gotcha, library, entitlements, paywall, scope]
status: superseded
---

# The library's Pro gate is a placeholder seam, not a real entitlement check

> **Superseded 2026-08-17 by the `pro-gating` agent (Phase 3).**
> `LibraryProAccess.swift` and the `\.libraryProAccess` environment key are deleted.
> `DocumentDetailView` now reads the entitlement through
> `RedactApp/Features/Library/ProAccess.swift`. The remaining half of the problem — nobody
> installing `EntitlementStore` into the environment at the root — moved to
> [[pro-gating-cross-lane-dependencies]]. Everything below is kept as the record of why the
> seam existed.

## What

`DocumentDetailView` shows the **redaction audit log** only to Pro users. It reads
`@Environment(\.libraryProAccess)`, declared in
`RedactApp/Features/Library/LibraryProAccess.swift`, whose default value is `false`.

**Nothing sets it.** Today every user — paying or not — sees the locked state.

## Why it was done this way

`Core/Entitlements/**` is the `feature-paywall` agent's allowlist and does not exist yet
(Phase 3, F10). Two alternatives were rejected:

- **Create `Core/Entitlements/` from the library agent.** A scope violation under
  `CLAUDE.md` rule 8, and it would collide with whatever the paywall agent declares.
- **Declare a shared `\.isPro` environment key.** Same collision, one file later: two
  declarations of the same key name in one module is a redeclaration error, and this
  project already lost time to exactly that with two `Models.swift` files.

So the dependency is expressed as a **feature-scoped** key with a name nothing else is
likely to choose, and a default that fails *closed*. An unwired build under-delivers to a
paying user, which is visible and fixable; a default of `true` would give a paid feature
away silently.

The locked state is not a dead end: it routes through `AppCoordinator.presentPaywall()`,
which is wired from Phase 2 onward, so `CLAUDE.md` rule 10 holds.

## The fix, when Phase 3 opens

One line in `RootView`, next to the other environment installs:

```swift
.environment(\.libraryProAccess, entitlements.isPro)
```

Then delete nothing — the key stays as the library's local read of a global fact. If the
paywall agent prefers a single app-wide key, replace the `EnvironmentKey` in
`LibraryProAccess.swift` with a `var` that forwards to theirs.

## How it will be noticed if forgotten

A Pro subscriber opens a saved document and sees "See what Pro includes". Worth an explicit
check in the Phase 3 verification pass rather than trusting anyone to remember.

**Related:** [[DEC-005-bounded-loop]] [[2026-08-17-01]]
