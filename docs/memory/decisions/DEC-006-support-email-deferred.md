---
id: DEC-006-support-email-deferred
date: 2026-08-17
phase: 3
tags: [decision, deferred, privacy, app-store]
status: deferred
---

# DEC-006 — Support email: personal address for now, alias revisited later

## Decision

`rsenthil2504@gmail.com` is published as the support contact on
`https://selvar2.github.io/redact-revenue-cat/support.html` and will be used in App Store Connect.

**Deliberately deferred, not overlooked.** Revisit after submission.

## The tradeoff

Apple requires a working support contact in App Store Connect metadata, and a support URL that
resolves. There is no way to ship without publishing *some* reachable address.

The cost of a personal address on a public page: scrapers harvest it, and it is permanent — the
address stays in Git history and in web archives even if the page changes later. Once published,
it cannot be unpublished.

The cost of doing it properly now: setting up a dedicated alias with forwarding is 15–30 minutes of
work on a critical path that has an App Review deadline at 2026-09-05. It changes nothing about
whether the app is approved.

## Why deferring is the right call here

The address is already public in other contexts and the marginal exposure is small. The submission
deadline is not movable and App Review latency is the project's dominant risk — see [[plan]].
Spending critical-path time on inbox hygiene while the paywall is unbuilt is the wrong order.

## What to do when revisiting

1. Create a dedicated address — `support@` on a custom domain, or a Gmail alias with forwarding
2. Update `support.html`, `privacy.html`, and `terms.html` on the `gh-pages` branch
3. Update the support email in App Store Connect (metadata-only change; no new build needed)
4. Consider an obfuscated `mailto:` or a contact form to reduce scraping

Steps 1–3 are all doable after the app is live. Nothing here blocks submission, which is precisely
why it waits.

**Related:** [[legal-urls-not-published]] · [[DEC-004-no-network]]
