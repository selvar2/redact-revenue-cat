---
id: phase-5-guide-for-kids
date: 2026-08-18
phase: 5
tags: [phase-doc, kids, explainer, testflight]
status: in-progress
audience: curious 10-year-olds
---

# Phase 5 — Four things went wrong, and three of them said nothing 🤫

> Grown-up versions: [[phase-5-non-technical]] · [[phase-5-technical]]

## What we were trying to do

Until now, Redact only ever ran on a **pretend iPhone** — a fake phone that lives inside a computer.
Pretend phones are genuinely useful. But they can't tell you whether an app *feels* nice to hold, or
whether the camera works properly, or whether buying something actually works.

So this phase was about getting it onto a **real phone**.

Apple has a thing for exactly this called **TestFlight**. Think of it as a secret door into the App
Store. You can send your app to a few friends before the whole world can see it. If something's
wrong, only your friends find out — not everyone. 😅

**Good news: it worked!** Apple looked at our app and stamped it `VALID`, which means "yep, this is
a real, properly-made app."

But getting there took **four** tries. And that's the story worth telling.

## Problem 1: the invisible dialog box 🪟

The computer just... stopped. Not slow. **Stopped.**

I waited. Nothing. Waited more. Still nothing.

Turns out the Mac had popped up a little box asking for a password — but the program I was watching
never mentioned it. It was waiting patiently for someone to type something, and I was waiting
patiently for it to finish. We could have waited forever! 😄

**Lesson:** if something is taking *far* too long, don't just wait harder. Go and look at what it's
actually doing.

## Problem 2: the key in the locked box 🔐

To put an app on a phone, Apple makes you **sign** it — like signing your name on your homework so
the teacher knows it's really yours.

But our signature key was locked inside a *different* box, with a password nobody could remember.

We could have spent hours hunting for that password. Instead we asked Apple for a **second key**.
Apple lets you have two! So we just... used the other one. 🔑

**Lesson:** when you're stuck on a locked door, check whether there's another door. Sometimes the
answer isn't "try harder", it's "go around".

## Problem 3: two tools with the same name 🔧🔧

The computer said:

> **"Copy failed"**

That's it. That's the whole message. Thanks, computer. 🙄

The real answer was hiding in a diary file buried deep in a folder nobody looks in. And it was
delightfully silly:

There were **two different copies of the same tool** on the Mac — both called `rsync`, both for
copying files. One was Apple's. One came from somewhere else. They were *slightly* different
versions, and they used **different words for the same thing**.

It's like one person saying "rubber" and the other saying "eraser". Same object! But if you insist
on your word, the other one just stares at you blankly. That's exactly what happened, and the whole
build gave up.

**Lesson:** when an error message is unhelpfully short, the real answer is usually written down
somewhere longer. Go find the longer thing. 📖

## Problem 4: the app had no face 😶

This was the sneakiest one. And it was **our own mistake**.

Every app has an **icon** — the little picture you tap on your home screen. Ours had an empty space
where the picture should be. We'd built the frame and never put the photo in.

Here's the horrible part: **Apple didn't tell us.**

We sent the app. The computer said "Sent successfully!" ✅ Everything looked perfect.

And then... nothing. The app just never showed up. No error. No warning. No red text. Just silence,
forever.

That's the *scariest* kind of problem. A problem that shouts at you is easy — you know it's there!
A problem that smiles and says "all good!" while quietly doing nothing? That one can waste your
entire day.

**So we made the icon.** And we did it in an interesting way: instead of drawing it by hand, we wrote
a tiny program that *paints* it — using the exact same colours the app uses inside. That way the
icon can never accidentally look like a different app. 🎨

Here's how we proved it was really there this time: the app file got **bigger**. It went from
11,568,981 to 12,021,381 — about 450,000 extra. That extra chunk *is* the picture. We didn't hope it
worked. We measured it.

## The big pattern 🔍

Look back at those four problems.

**Three of them said nothing at all.** One froze silently. One said "Copy failed", which was
basically a lie. One reported complete success while doing nothing.

Only *one* of them actually told us what was wrong.

This keeps happening in this project! Earlier on, our app claimed it had hidden someone's private
information — and had left their **name** sitting right there. Another time it missed a **bank
account number** completely. Neither one complained. Both looked perfectly fine.

So here's the rule we keep coming back to, and it's a genuinely useful one for anything you ever
build:

> **Don't believe something worked just because nothing complained.
> Go and check the actual result.**

We didn't ask our own computer "did you send it?" — of course it says yes. We asked **Apple's**
computers "did you receive it?" That's a completely different question, and it's the one that
matters.

## Where we are now

```
✅  App built
✅  App signed
✅  Sent to Apple
✅  Apple says: VALID ← the app is real and accepted!
⬜  Put it on a real phone
⬜  Write the shop description
⬜  Apple reads it properly (like marking homework)
⬜  LIVE for everyone 🌍
```

Nearly there! The hard, fiddly, invisible part is **done**. What's left is mostly writing — telling
people what the app does. 📝

**Related:** [[phase-4-guide-for-kids]]
