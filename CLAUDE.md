# CLAUDE.md — Project Rules for Redact

> Read this file **first**, every session. Then read `docs/memory.md` for current state.
> These rules are not suggestions. A change that violates one is a defect, even if it compiles.

## What this project is

**Redact** — an iOS app that finds personal information in documents and photos and removes it
**irreversibly**, entirely on-device. Built for the RevenueCat Shipaton 2026 hackathon.

- Bundle ID: `com.senthilnathanraja.redact`
- Min iOS: **17.0**. iOS 26+ features are additive and must be `#available`-gated.
- Deadline: App Store submission by **2026-09-05**. Shipaton closes 2026-09-30.

## The Ten Rules

### 1. No network. Ever.
This app makes **zero** network requests, with exactly one exception: the RevenueCat SDK.
No analytics, no crash reporters, no font CDNs, no telemetry, no "just this once".
This is what lets us answer **"No Data Collected"** on Apple's App Privacy questionnaire truthfully,
which is our single biggest App Review advantage. Adding a network call destroys it.

### 2. Redaction must actually destroy data.
Drawing a black rectangle over text is **not** redaction — the text survives underneath and is
recoverable with `pdftotext` or by selecting it. Every redaction path must:
- rasterise or delete the underlying content, never composite over it
- strip metadata: EXIF, GPS, PDF `/Info`, XMP, embedded thumbnails
- flatten the output so no layer retains the original
- be covered by a test that OCRs our own output and asserts the secret is **gone**

If you are unsure whether a code path truly destroys data, it does not ship.

### 3. Design tokens are law.
Never hardcode a colour, font, radius, spacing value, or animation curve in a view.
Everything comes from `DesignSystem/`. If a token doesn't exist, add it there first.
Source of truth for the visual language: `docs/memory/decisions/DEC-002-design-language.md`.

### 4. Accessibility is a requirement, not a polish task.
Dynamic Type, VoiceOver labels on every interactive element and every detected PII span,
`@Environment(\.accessibilityReduceMotion)` honored on all animation, minimum 4.5:1 contrast.
A view without accessibility support is incomplete.

### 5. Swift 6 strict concurrency.
No `@unchecked Sendable` escapes. No `DispatchQueue` where a structured `Task` fits.
UI types are `@MainActor`. Vision/PDF work happens off the main actor and returns `Sendable` values.

### 6. Log to memory as you work.
Every meaningful change appends to `docs/memory/sessions/<today>-NN.md` **as it happens**, not at the end.
Every entry: what, why, real code, real commands with real output, exact next step.
A subagent's final action before returning is writing its memory entry. See `agent.md`.

### 7. You may not mark your own work verified.
`feature_list.json` states: `not_started → in_progress → built → verified`.
Builders may write up to `built`. **Only the verifier agent writes `verified`.**

### 8. Stay inside your scope.
`AGENTS.md` gives each agent an explicit file allowlist. Editing files outside it is a defect,
not initiative. If you believe an out-of-scope change is needed, log it in
`docs/memory/gotchas/` and stop.

### 9. Never commit secrets.
`.p8` keys, API Key IDs, Issuer IDs, RevenueCat secret keys — none of these enter the repo, ever.
RevenueCat **public SDK keys** are safe to commit (they are public by design). Everything else lives
in the keychain or in an untracked local config. `*.p8` is in `.gitignore` from commit one.

### 10. No placeholders in shippable code.
No "coming soon", no dead buttons, no lorem ipsum, no TODO in a user-visible string.
App Review rejects on this (Guideline 4.2), and it is trivially avoidable.

## App Review checklist — every UI change is checked against this

- [ ] Paywall has a visible **Restore Purchases** button
- [ ] Paywall shows **Terms of Use (EULA)** and **Privacy Policy** links
- [ ] Paywall states price, billing period, and auto-renewal in plain text
- [ ] Camera / photo purpose strings explain *why*, specifically
- [ ] Photo access uses the **limited** picker, not full-library authorization
- [ ] Sample document ships so a reviewer sees value in under 30 seconds with zero setup
- [ ] No screen can dead-end; every error state has a recovery path

## Definition of Done

A feature is done when **all** are true:

1. `./verify.sh` exits 0 (build + tests + simulator boot)
2. It works when driven in the iOS 26.5 simulator — observed, not assumed
3. Accessibility pass: VoiceOver + largest Dynamic Type
4. A memory entry exists explaining what and why
5. The **verifier agent** has marked it `verified` in `feature_list.json`

"It compiles" is not done. "It should work" is not done.

## Commands

```bash
./init.sh          # session bootstrap — run first, every session
./verify.sh        # the gate: build + test + simulator
python3 tools/memory_index.py build      # rebuild memory retrieval index
python3 tools/memory_index.py query "…"  # search project memory
```

## Where things live

| Path | What |
|---|---|
| `RedactApp/` | the Xcode project and all Swift source |
| `docs/memory.md` | current state — **read after this file** |
| `docs/memory/decisions/` | why things are the way they are |
| `docs/phases/phase-N/` | the three-doc triad per phase |
| `feature_list.json` | machine-readable feature state |
| `AGENTS.md` | agent roster and scope boundaries |
| `agent.md` | system prompt for coding agents |
| `instructions.md` | human runbook (build, sign, ship) |
