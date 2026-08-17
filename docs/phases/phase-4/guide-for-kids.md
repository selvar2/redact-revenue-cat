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

---

## Update — we put things on the shelf! 🛒

Last time, the shop was connected but completely **empty**. Like a shop with a working till and
nothing to buy.

Now there are two things on the shelf:

```
   ┌──────────────────────┐     ┌──────────────────────┐
   │  Redact Pro          │     │  Redact Pro          │
   │  MONTHLY             │     │  YEARLY              │
   │                      │     │                      │
   │      ₹29             │     │      ₹29             │
   │    each month        │     │    each YEAR         │
   └──────────────────────┘     └──────────────────────┘
```

Look at those two carefully. Same price — but one lasts a *month* and the other lasts a whole
**year**! The yearly one is obviously the better deal. (Twelve months of the monthly one would be
₹348. So the yearly one saves you about 92%. That's a lot!)

## Why not ₹1? 🤔

We actually wanted to charge just **₹1**. Here's the reason, and it's quite funny.

To finish the last step of this whole project, the developer has to buy his own app. With his own
money! So naturally he'd like it to be as cheap as humanly possible. 😄

But Apple doesn't let you pick any price you want. Imagine a vending machine where the buttons are
already made: 29, 49, 99, 149… and there's simply **no button for 1**. You can only press a button
that exists.

The cheapest button in India is **₹29**. So that's what we pressed — twice.

## The clever bit

Remember how the app shows "Save 92%" on the yearly plan?

We never *typed* 92 anywhere. The app works it out itself: it looks at both real prices, does the
sum, and writes the answer on the screen.

Why bother doing it the hard way? Because if someone changes the prices tomorrow, a typed-in number
would become a **lie** — the screen would promise a discount that isn't real. A number the app
calculates can never lie. It just quietly becomes the new correct answer. ✅

That's a genuinely good habit: **don't write down answers you can work out.**

## Oops — a good catch 🔍

Someone said "both prices are done!" and it *looked* done. There was even a screenshot.

But when we opened each product separately and actually looked… only **one** of them had a price.
The other had none at all. The screenshot had been of the finished one.

Nobody was being sneaky! It's just genuinely easy to look at a screen, see something that seems
right, and move on.

This is the third time checking properly has saved us. Earlier we caught the app leaving someone's
**name** on a document it claimed to have cleaned, and a **bank account number** it hadn't even
noticed. Neither one complained. Neither one showed an error.

**The scariest problems are the quiet ones.** So we look. Every time. 👀

## What's left before the whole world can use it?

```
✅  Shop connected
✅  Things on the shelf
⬜  Write the labels        (what each plan is called and does)
⬜  Get a new safety key    (the old one opens too many doors)
⬜  Test flight ✈️           (a few real phones try it first)
⬜  Apple checks it         (like a teacher marking homework)
⬜  LIVE! 🌍
```

The "test flight" is my favourite bit. Before an app goes out to everyone, it goes to a small group
of real people on real phones. Simulators on a computer are brilliant, but they can't tell you
whether something feels awkward in an actual hand. 🤳
