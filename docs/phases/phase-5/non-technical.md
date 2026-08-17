---
id: phase-5-non-technical
date: 2026-08-18
phase: 5
tags: [phase-doc, non-technical, business, testflight]
status: in-progress
audience: colleagues, management
---

# Phase 5 — In plain language

> For engineers: [[phase-5-technical]] · For a 10-year-old: [[phase-5-guide-for-kids]]

## Where we are

**The app has been accepted by Apple's systems and is ready to be installed on real phones.**

Apple marks a submitted build as `VALID` once it has passed their automated checks. Ours is
`VALID`. The project's status indicator moved from **red** to **yellow** — yellow meaning "nothing is
broken, you just have paperwork left".

## What this phase was for

Everything until now happened on a simulator — a fake iPhone running on a laptop. Simulators are
excellent, but they cannot tell you whether an app feels right in a hand, whether the camera behaves,
or whether a purchase completes on a real Apple ID.

TestFlight is Apple's answer: a private version of the App Store where you send a build to a small
number of real people on real devices before anyone else sees it.

It is also cheap insurance. TestFlight builds get a lighter review from Apple, so if something in
the app offends their rules, you usually learn it here rather than burning a full review cycle — and
review cycles are the only thing standing between this project and its deadline.

## It took four attempts, and that is the interesting part

None of the four failures were about the app's code. The app was fine throughout. Every one was
about the machinery of *packaging and delivering* it — and three of the four failed **silently**.

**1. A password dialog nobody saw.** The build process froze. Not slowly — completely. macOS had put
a password prompt on screen and was waiting; the tooling gave no indication. Discovered by checking
which programs were running rather than by waiting longer.

**2. A signing certificate locked in the wrong place.** Apple requires apps to be cryptographically
signed, proving they came from a verified developer. The key for that signature was inside a
separate password-protected store left over from other software — and the password was forgotten.

Rather than hunt for it, we had Apple issue a second certificate. Apple permits two. Nothing that
relied on the old one broke, and no forgotten password was needed.

**3. The wrong copy of a utility program.** The build failed with the message *"Copy failed"* and
nothing else. The truth, found in a log buried several folders deep: two different versions of a
common file-copying tool were installed, and Apple's build system reached for one but got the other.
They disagreed about the name of a setting, and the build died.

The lesson is about the message, not the tool: **"Copy failed" pointed nowhere near the actual
problem.** Two reasonable guesses were tried and discarded before reading the real log.

**4. The app had no icon.** The most consequential one, and it was our own oversight.

The project had a *slot* for an app icon but no actual picture in it. Apple rejects any app without
one — and rejects it **quietly**. The upload reported complete success. The build simply never
appeared, with no error, no warning, and no indication anything was wrong. The only notification is
an email.

Fixed by generating the icon from the app's own design colours, so it can never look like a
different product than the app itself.

## The pattern worth taking away

Three of these four problems reported success, or reported nothing at all.

That is the recurring theme of this entire project. Earlier phases caught an app that claimed to have
removed private information while leaving a name visible, and a bank account number it never noticed
at all. Neither complained. Neither logged anything.

**The habit that keeps catching these is refusing to accept a claim of success without checking the
result at its destination.** Here that meant asking Apple's servers whether the build existed, rather
than trusting the upload tool that said it had sent it.

We also strengthened the automatic checks so a missing icon fails immediately in future, instead of
surfacing as silence from Apple hours later.

## What is left before the app is public

| Task | Effort |
|---|---|
| Invite testers on TestFlight and install on a real phone | minutes |
| Descriptions for the two subscription plans | ~10 minutes of writing |
| Store listing: description, keywords, screenshots | a couple of hours |
| Submit for Apple's review | minutes to submit, 24–48h to hear back |

Then, once it is live, one purchase completes the final hackathon milestone.

**Related:** [[phase-4-non-technical]] · [[plan]]
