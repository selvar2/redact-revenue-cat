---
id: DEC-005-bounded-loop
date: 2026-08-17
phase: 0
tags: [decision, process, agents]
status: accepted
---

# DEC-005 — Bounded verify→fix loop: one pass each, seven runs total

## Decision

Each phase runs **BUILD → VERIFY → FIX → close**, with the verifier and fixer each executing
**exactly once**. Plus one whole-application verification before submission.

**Total across the project: 6 phase verifications + 1 final = 7 verifier runs.**

## Why bounded

Unbounded verify→fix loops are seductive and usually wrong. They:

- **rarely converge** — each fix perturbs the code, generating fresh findings, and the loop finds
  new things to complain about indefinitely
- **burn budget fast** — verification is the most expensive agent role, since it must read everything
- **produce diminishing returns** — pass 1 catches the real defects; pass 3 catches style opinions
- **create false confidence** — "it survived five rounds" sounds rigorous but often means five rounds
  of an agent grading its own ecosystem's work

A single adversarial pass by a genuinely independent agent catches more than three passes by an agent
that has been marinating in the codebase.

## What does the repetitive checking instead

`verify.sh`. Deterministic, free, and runnable on every save: build, tests, secret scan, no-network
grep, placeholder grep, memory index. Machines do repetition; agents are spent on judgment.

This is the actual division of labour:

| Concern | Checked by | Frequency |
|---|---|---|
| Does it build? Do tests pass? | `verify.sh` | every change, free |
| Secrets, network calls, placeholders | `verify.sh` | every change, free |
| Is the code truthful? Does it meet acceptance? | verifier agent | once per phase |
| Will Apple reject this? | verifier agent | once per phase + final |

## Escalation instead of iteration

Anything the fixer cannot resolve in its single pass:

1. is written to `docs/memory/gotchas/<slug>.md` with the full context
2. is escalated to the **human** by name
3. does **not** silently trigger another agent round

This is deliberate. An unresolved finding is a decision point, and decision points belong to the
person shipping the app, not to a loop.

## Independence requirement

The verifier runs with **fresh context** and read-only tools. It never sees the build conversation.
An agent that helped write the code will rationalise its own choices — that is not a character flaw,
it is how context works. Independence has to be structural.

**Related:** [[AGENTS.md]] · [[CLAUDE.md]]
