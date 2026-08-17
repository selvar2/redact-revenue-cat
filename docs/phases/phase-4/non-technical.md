---
id: phase-4-non-technical
date: 2026-08-17
phase: 4
tags: [phase-doc, non-technical, business]
status: complete
audience: colleagues, management
---

# Phase 4 — In plain language

> The same story for engineers: [[phase-4-technical]] · For a 10-year-old: [[phase-4-guide-for-kids]]

## The one-sentence version

Redact was practising on a pretend shop. Phase 4 connected it to Apple's real one.

## What actually changed

Almost nothing — and that was the point.

Up to now the app could show a price, take a "payment", and unlock its paid features. But the shop
on the other end was a rehearsal room RevenueCat provides for exactly this purpose. No real money
could move through it.

Phase 4 replaced one line of configuration: a code that said *"talk to the practice shop"* became a
code that says *"talk to Apple's real store"*. Everything else — the prices, the plans, the paid
features, the receipt handling — was already built to production standards, so none of it needed
touching.

**This is what good preparation looks like from the outside: the risky-sounding step turns out to be
boring.**

## The mistake we avoided

The developer already had a security file left over from an earlier project and asked, reasonably,
whether it could be reused here.

It could not — and this is the part worth understanding, because **using the wrong one would not
have shown an error.**

Apple issues two different security files that look completely identical:

- One is a **management pass**. It lets software manage the app: upload new versions, send test
  builds, edit the store listing.
- One is a **purchase pass**. It lets Apple confirm to us that a payment genuinely happened.

We had the management pass. We needed the purchase pass, and it had never been created.

Had we used the wrong one, the app would have looked perfectly healthy — and customers would have
paid and received nothing. No crash, no alert, no log entry. Just people out of pocket and a support
inbox filling up.

We checked instead of assuming, found the gap, created the correct file, and confirmed with
RevenueCat that it reads as valid.

## How we know it genuinely worked

We did not take the app's word for it. We ran it and watched what it said to Apple's payment system.

Before, the app never contacted Apple at all — it was talking to the rehearsal room. Now the logs
show it connecting to Apple's payment queue, identifying which country's store it is in, and asking
about transactions. That conversation is the proof, and it is exactly what the hackathon's fourth
milestone asks for.

RevenueCat's own setup checklist agrees: it moved from 3 of 6 complete to 4 of 6.

## Where the money will actually go

Worth restating plainly, because it is the part people usually get wrong:

- A customer pays **Apple**, never us. Apple is legally the seller.
- Apple keeps 15–30% and sends the rest to an Indian bank account in rupees, monthly.
- **RevenueCat never touches the money.** It only tells the app "this person has paid" and gives us
  the sales figures.
- No payment gateway was ever needed. Stripe not being available in India was never a real obstacle
  — it simply was not part of this route.

## Milestones

| # | Milestone | Status |
|---|---|---|
| 1 | Registered for the hackathon | ✅ |
| 2 | RevenueCat project created | ✅ |
| 3 | First practice purchase | ✅ |
| 4 | **Connected to the real App Store** | ✅ **this phase** |
| 5 | First real purchase | remaining |

Milestone 5 needs the app live on the App Store. That is Phase 5: a test flight to a real device
first, then submission for Apple's review.

## What still has to happen

**The products themselves do not exist yet in Apple's system.** We have created the shelf; nothing
is on it. Until the monthly and yearly plans are added, no purchase can complete. That is the next
task and it is straightforward.

Three other open items:

1. **The paywall is not yet designed in RevenueCat's visual editor.** The app has a perfectly good
   built-in version, but designing it in the dashboard means the price presentation can be changed
   without shipping a new app version — a capability one of the hackathon awards specifically
   rewards.
2. **That old management pass should be replaced.** It grants full administrative control, more than
   anything needs, and it has been shared around. Replacing it with a narrower one is a few minutes
   of work and reduces risk meaningfully.
3. **Five other people hold administrator access to the developer account.** Each can see this app,
   publish versions of it, change its pricing, and read its financial reports. That may be entirely
   intentional — but it is worth a deliberate look rather than an assumption, given prize money is
   involved.

**Related:** [[phase-3-non-technical]] · [[plan]]
