---
id: phase-4-guide-for-kids
date: 2026-08-17
phase: 4
tags: [phase-doc, kids, explainer]
status: complete
audience: curious 10-year-olds
---

# Phase 4 — The two keys that looked the same

> Grown-up versions: [[phase-4-non-technical]] · [[phase-4-technical]]

## The story so far

We built an app called **Redact**. You show it a photo of a document, it finds the private bits —
your name, your phone number, your bank number — and paints over them with a marker that can never
be rubbed off.

Most of the app is free. But if you want the extra-good version, you can pay a little every month.
And that means the app needs to be connected to a **shop**.

## The pretend shop

Here's the thing about shops: you don't want to practise with real money.

Imagine you're learning to work a till at a shop. Would you practise with real customers and real
banknotes? Of course not. You'd practise with a toy till and pretend money first.

That's what we'd been doing. RevenueCat (the company that helps apps sell things) gives you a
**pretend shop**. Our app was buying things with pretend money and it all worked beautifully.

Phase 4 was the moment we said: *okay — we've practised enough. Connect it to the real shop.*

## How much code did we change?

Ready for this?

**One line.**

```
before:  talk to the PRETEND shop
after:   talk to the REAL shop
```

That's genuinely it. Nothing else in the whole app had to change.

That sounds too easy, but it's easy *because* we were careful earlier. Remember when you tidy your
room properly, and then finding your football boots takes two seconds? Same idea. We'd put all the
shop settings in **one single place** on purpose, so that when this day came, there was exactly one
thing to change instead of a hundred.

Good preparation is boring. Boring is the goal. 🎯

## Now the interesting bit: the two keys 🔑🔑

To connect to the real shop, Apple gives you a **key**. It's not a metal key — it's a tiny file on
the computer. It proves you're really you.

The developer already had one of these keys from a different project. So he asked: *can we just use
this one?*

Good question! Let's look at them.

```
        KEY A                          KEY B
   ┌─────────────┐                ┌─────────────┐
   │  🔑 .p8     │                │  🔑 .p8     │
   │             │                │             │
   │  looks the  │                │  looks the  │
   │    same     │                │    same     │
   └─────────────┘                └─────────────┘
```

They look **identical**. Same size. Same kind of file. If you opened both, you'd see the same sort
of scrambled letters. There is nothing inside either one that says what it's for.

But they do completely different jobs:

- **Key A** is like the key to the **staff room**. It lets you into the back of the shop — put new
  things on the shelves, change the posters in the window, let new staff in.
- **Key B** is like the key to the **till**. It's the one that lets the shop check that a payment
  really happened.

We had the staff room key. We needed the till key. And nobody had ever made a till key at all.

## Why this really, really mattered

Here's the scary part.

If we'd used the wrong key, **nothing would have looked broken.**

No error message. No red warning. No crash. The app would have looked completely happy.

But when someone paid their money… they'd get **nothing**. The shop couldn't check the payment, so
it wouldn't unlock anything. Real people, paying real money, getting nothing back — and no clue why.

That's the sneakiest kind of problem there is. A problem that *shouts* is easy. A problem that stays
quiet and lets people down is much worse.

So we didn't guess. We went and **looked**. And it turned out Apple does leave you one clue — in the
file's name:

```
AuthKey_CDCMHRBW3C.p8          ← "Auth"         = the staff room key
SubscriptionKey_BU27GRYDV3.p8  ← "Subscription" = the till key  ✅
```

We made the till key, and it worked. 🎉

**The lesson:** when two things look the same but do different jobs, don't guess. Go and check. It
takes two minutes, and it can save someone else a very bad day.

## How did we know it *actually* worked?

We could have just said "the app didn't crash, so it must be fine!"

That's not proof. That's hope.

Instead we did something better. Computers keep a **diary** of everything they do. So we opened the
app's diary and read it. And there it was:

> *"Talking to Apple's payment system…"*
> *"Which country's shop am I in? … the USA one."*
> *"Any purchases I should know about?"*

Before Phase 4, **none of those sentences existed** — because the app had never spoken to the real
shop in its life. Now it chats to it happily.

That's the difference between *hoping* and *knowing*. Always try to know. 🔍

## One more thing: keeping the key safe

The till key is a bit like the password to your house. You wouldn't:

- write it on your school bag ❌
- post it on the internet ❌
- leave it lying around where anyone could copy it ❌

So we were careful. The key went straight from Apple to the shop system and **never** got saved into
the project folder — because that folder gets published on the internet for everyone to read.

We even added an automatic guard dog 🐕 that checks *every single time* and refuses to let anything
through if it spots a key sneaking in. Not because we don't trust ourselves — but because everybody
makes mistakes eventually, and a guard dog doesn't get tired at 2am.

## Where we are now

```
✅  1. Signed up
✅  2. Made the shop account
✅  3. Bought something with pretend money
✅  4. Connected to the REAL shop      ← we just did this!
⬜  5. Someone buys it for real
```

Four out of five! 🎊

## What's left

The shop is connected… but **the shelves are still empty**. We've built the shop and plugged in the
till, but we haven't actually put the monthly plan and the yearly plan *on the shelf* yet. Until we
do, nobody can buy anything — there's nothing to pick up!

That's the very next job. Then the app goes to Apple, who check it over like a teacher marking
homework, and if they're happy — it goes live for the whole world. 🌍

**Related:** [[phase-3-guide-for-kids]]
