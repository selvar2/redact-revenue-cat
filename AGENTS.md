# AGENTS.md — Roster, Scope Boundaries, and the Loop

All agents load `agent.md` as their system prompt, then obey the allowlist below.
**Editing a file outside your allowlist is a defect.** Parallel agents rely on these boundaries;
crossing one silently destroys another agent's work.

## The loop — bounded, executed once per phase

```
        ┌──────────────────────────────────────────┐
        │  BUILD   parallel builders, scoped       │
        └────────────────────┬─────────────────────┘
                             ▼
        ┌──────────────────────────────────────────┐
        │  VERIFY  ONE independent pass. Read-only │
        └────────────────────┬─────────────────────┘
                             ▼
        ┌──────────────────────────────────────────┐
        │  FIX     ONE pass. Applies findings only │
        └────────────────────┬─────────────────────┘
                             ▼
              unresolved → gotchas/ + escalate to human
                             ▼
                        CLOSE PHASE
```

**Anti-looping rules — these exist because unbounded verify→fix cycles burn budget and rarely converge:**

- The verifier runs **exactly once per phase**. Not until-clean. Not best-of-N.
- The fixer applies findings in **exactly one pass**. It does not re-verify its own fixes.
- Anything unresolved after that pass is logged to `docs/memory/gotchas/` and escalated to the
  **human**. It does **not** silently trigger another round.
- Exactly **one** additional whole-application verification runs at the end of Phase 5,
  immediately before App Store submission.
- Budget across the entire project: **6 phase verifications + 1 final = 7 verifier runs.**

Repetitive checking is done by `./verify.sh` — deterministic, free, run as often as you like.
Agents are spent on judgment; scripts on repetition.

## Builder agents

| Agent | Owns (allowlist) | Must not touch |
|---|---|---|
| `scaffold` | `RedactApp.xcodeproj`, `RedactApp/App/`, `Package.swift` | any feature source |
| `design-system` | `RedactApp/DesignSystem/**` | features, Core |
| `detect-engine` | `RedactApp/Core/Detection/**`, `Tests/DetectionTests/**` | UI, DesignSystem |
| `redaction-core` | `RedactApp/Core/Redaction/**`, `Tests/RedactionTests/**` | UI, DesignSystem |
| `persistence` | `RedactApp/Core/Persistence/**` | UI, Detection, Redaction |
| `feature-scan` | `RedactApp/Features/Scan/**` | Core internals, other features |
| `feature-editor` | `RedactApp/Features/Editor/**` | Core internals, other features |
| `feature-export` | `RedactApp/Features/Export/**` | Core internals, other features |
| `feature-library` | `RedactApp/Features/Library/**` | Core internals, other features |
| `feature-paywall` | `RedactApp/Features/Paywall/**`, `RedactApp/Core/Entitlements/**` | everything else |
| `onboarding` | `RedactApp/Features/Onboarding/**`, `RedactApp/Resources/**` | logic modules |
| `docs-writer` | `docs/**` | all source |

Builders may advance `feature_list.json` to `built`. **Never to `verified`.**

## The verifier — independent by construction

**Runs once per phase. Read-only tools. Fresh context — it never sees the build conversation.**

That independence is the entire point. An agent that wrote the code will rationalise its own choices;
an agent that has never seen it will not.

It is prompted **adversarially**: *find what is broken*, default to failing, treat "looks fine" as a
failure to look hard enough.

It checks:

1. **Truthfulness** — does the code do what its memory entry claims? Run `./verify.sh` and read the output
2. **Rule compliance** — all ten `CLAUDE.md` rules, especially no-network, real-redaction, design-tokens
3. **The App Review checklist** in `CLAUDE.md` — this is where "will Apple reject this?" gets answered
   by something other than optimism
4. **Accessibility** — VoiceOver labels present, Dynamic Type, `reduceMotion` honored
5. **Scope violations** — did any builder edit outside its allowlist?
6. **Redaction irreversibility** — does the destroy-data test actually exist and actually pass?

Output: a findings list, severity-ranked, each with file, line, and a concrete failure scenario.
It **fixes nothing**. It is the only agent permitted to write `verified` into `feature_list.json`.

## The fixer

Runs once, immediately after the verifier. Input is the findings list, nothing else.
Applies fixes in one pass. Does not re-verify. Does not expand scope beyond the findings.
Anything it cannot resolve → `docs/memory/gotchas/` + escalate to the human by name.

## Every agent, without exception

Writes its memory entry to `docs/memory/sessions/<date>-NN.md` as its **final action** before
returning. Format is specified in `agent.md`. No entry means the work is invisible to the next
session, which means it may as well not have happened.
