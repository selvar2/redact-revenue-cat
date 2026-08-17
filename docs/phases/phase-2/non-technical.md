---
id: phase-2-non-technical
date: 2026-08-17
phase: 2
audience: colleagues, management, non-engineers
tags: [phase-2, product, commercial, plain-language]
status: complete
---

# Phase 2 — The App Now Exists

> For anyone who needs to explain this product without writing code.
> Siblings: [[phase-2-technical]] (for engineers) · [[phase-2-guide-for-kids]] (for a ten-year-old).
> Previous phase: [[phase-1-non-technical]].
> No prior knowledge assumed. Every technical word is defined the first time it appears.

## The headline

Phase 1 built an engine. Phase 2 built the car around it.

You can now open Redact on an iPhone, take a photo of a document or pick a PDF, watch it find the
personal details, tap the ones you disagree with, and share a clean copy. It saves what you made,
lets you find it again, and genuinely deletes it when you say delete.

We know it works because **we drove it**, not because it compiled. Someone installed the app,
tapped through it, then went into the phone's storage, pulled out the file the app had just
produced, and inspected it. That last step is the one nearly everybody skips — and it is the one
that found the most important problem of the entire project so far. More on that below, because it
is the best story we have.

## Why this product exists, in one idea

If you remember one thing from this document, make it this.

**A black box drawn over text does not remove the text.**

A digital document is a stack of layers, like a sandwich. The words sit on one layer. When you draw
a black rectangle over them in Preview, Acrobat, Markup, or the photo editor on your phone, you are
adding a *new layer on top*. The words are still underneath, complete and untouched.

```
  What you see                 What is actually in the file
  ─────────────                ────────────────────────────
  ┌───────────────┐            ┌───────────────┐  ← black rectangle (a separate layer)
  │  Name: ███████│            ├───────────────┤
  │  PAN:  ███████│            │  Name: Ananya │  ← the original text, untouched
  └───────────────┘            │  PAN: AZZPQ4821K
                               └───────────────┘
```

Anyone who receives that file can get the words back in seconds, with no skill at all: select and
copy across the black box, or click the rectangle and press delete, or run a free thirty-year-old
tool that dumps every word in the document and ignores anything drawn on top.

This is not theoretical. Sealed court filings, redacted legal settlements and government reports
have all leaked exactly this way — and they leaked because everyone in the chain believed the black
box was doing something it was never doing.

**Redact does not draw anything on top of anything.** It takes the picture apart into its individual
coloured dots, overwrites the dots covering your details with solid black — replaces them, does not
paint over them — and writes a brand-new file from those dots. There is no layer to peel off,
because there are no layers. There is nothing underneath, because there is no underneath.

That is the product's entire reason to exist, and it is also the easiest thing in the world to
demonstrate: hand someone a file "redacted" by any normal tool, let them copy the text out of it,
then hand them ours and watch them fail. Thirty seconds, no explanation needed.

## What was built this phase

Six pieces, built by six agents working in parallel, then independently reviewed.

| Piece | In plain terms |
|---|---|
| **Shared foundation** | The rules all the screens agree on: what a "document being worked on" is, how you move between screens, and one single route from "a file arrives" to "here is what we found in it". |
| **Scan / import** | Three ways to bring a document in: the camera (with the built-in document scanner that straightens the page), your photo library, or a PDF file. |
| **The editor** | The review screen. It shows the page with a coloured box around every detail we found, and you decide what stays and what goes. |
| **Export** | Turns your decisions into a real, permanently-changed file, saves it, and hands it to the share sheet. |
| **Library** | Everything you have made before, searchable, re-shareable, and deletable for real. |
| **Onboarding + sample document** | A three-screen introduction and a fake payslip built into the app, so anyone — including an App Store reviewer — can see the whole product work without a camera, an account, or any typing. |

### The sample document is a commercial decision, not a nicety

Apple's reviewers spend a very short time with each app. If the first thing they meet is a camera
permission prompt, some of them stop there. So the app ships with a fictional payslip for a made-up
employee at a made-up company, containing realistic-looking (but deliberately invalid) ID numbers.

The measured result: **cold launch to a working editor in three taps and about twenty seconds**, with
no camera, no photo permission, no account, and no typing. Two more taps produce a finished file.

It is also drawn in code rather than shipped as an image file, so anyone auditing the app can read
exactly which fake identifiers are inside it in a single screen — the right property for a file
whose whole job is to contain believable-looking personal information.

### The editor's signature moment

When the editor opens, a violet-to-amber line sweeps down the page like a scanner, and each detected
item appears as the line passes over it — top to bottom, in reading order — followed by a single
firm buzz as the bars land.

It is the screenshot that sells the app, and the one part of the design we spent real effort on. It
also does the right thing for people who need it to: if you have asked iOS to reduce motion (a
setting people with vestibular conditions rely on), the sweep is replaced by a gentle fade **and the
buzz does not fire** — a calm-down setting should not come with a punch in the hand. And touching
anything skips straight to the end. An animation must never make you wait to use a control.

### The problem Phase 1 escalated, now answered

Phase 1 found a real hole and deliberately did not fix it, because the fix was a product decision
rather than an engineering one:

> If someone imports a PDF that a *different* tool already "redacted" badly — with the fake black box
> described above — and asks us to work on a different page, we pass that bad page through untouched,
> fake black box and all. We never create that problem, but we can inherit it.

The decision taken was **detect and offer**. Before exporting, the app checks every page for marks
that might be hiding text. It only warns you when there is **actually text underneath the mark** —
which is the difference between a fake redaction and someone's signature on a blank line. Then it
tells you in plain English what it found and lets you choose: make those pages permanent too, or
leave them as they are.

Three things about that warning are deliberate and worth repeating to a customer:

- **It never says a file is clean when it isn't.** If you choose "leave as is", the screen tells you
  plainly that what is drawn on those pages can still be removed by whoever opens the file. Your
  call, honestly stated, no nagging.
- **It never shows you the hidden words.** The app counts the characters underneath the mark but
  never copies them out. Putting them in a warning message would re-expose the exact thing you were
  trying to protect.
- **It does not cry wolf.** A warning that fires on every signed contract teaches people to tap
  through it — and then they tap through the one that mattered.

## The best story from this phase: we caught ourselves lying

This is the part worth telling in a talk, an investor meeting, or a hiring pitch.

The build passed. All 86 automated tests passed. The gate was green. The app installed, launched,
and worked. By every normal measure, the phase was done.

Then the reviewer did the unglamorous thing: pulled the file the app had just produced out of the
phone's storage and looked at it, blown up, with their eyes.

```
Employee   Ananya Mehra          <- no bar at all
Date of Birth: 1███████          <- the first digit of the date survived
IFSC: Z███████                   <- the first character survived
```

Meanwhile the screen above it confidently said *"10 removed — there is nothing underneath them to
recover."*

Two separate faults with one appearance:

1. **The employee's name was never found at all.** The name-finding component built into iOS is
   trained on flowing prose — sentences. On a form, a name sits in a column with a printed label
   next to it and no sentence anywhere, and the component simply returns nothing. Our fix was to
   treat **the printed label itself as the evidence**: if a document says "Employee" and the next
   thing is a name-shaped word, that is a name — a rule that works in every language, which is
   exactly what a model trained on English prose does not.

2. **Every black bar was drifting slightly to the right**, enough to leave the first character of
   each ID number sticking out. The cause was arithmetic: we were estimating where each character
   sat by counting characters, but real type is proportional — an "i" is much narrower than a "W".
   The fix was to stop estimating and ask iOS's text engine to measure each character for us.

And the fix caused a worse bug before it caused a better one: asked to measure a single blank space,
the text engine cheerfully returns a box covering half the page, which produced an enormous bar over
the top of the document. Every ID number on the page contains a space. Now we never ask about
spaces, and we reject any measurement that lands outside the line it came from.

### The lesson that generalises

Here is the part that changes how we test everything from now on.

The engineer's first new test — the one meant to prove the leak was fixed — **passed on the broken
build.** They nearly shipped it as evidence.

The reason is subtle and important. Our tests check for leaks by running text-recognition over our
own output, the way an attacker would. But text-recognition ignores a single stranded character next
to a black bar. A file that visibly reads `Date of Birth: 1` gets reported back as
`Date of Birth:` — clean. **Every text-based check in the world is blind to a one-character leak,
and a one-character leak is the one that matters most**, because a leading digit narrows a guess
enormously.

So the new test does not read the output. It **counts colours**. It asks the phone to measure exactly
where each secret sits in the original, then checks that in the finished file that entire area is one
single flat colour. Nothing readable, nothing partially readable, nothing at all.

And the engineer verified the test could still fail: they deliberately put the bug back, watched the
test fail, then fixed it again. A test that passes on a broken build is worse than no test, because
it buys false confidence.

## Honest status

**Working, and observed rather than assumed:** the full loop, end to end. 98 automated tests, all
passing. The reviewer path — cold launch to finished, shared file — in five taps.

Things that are genuinely not finished, which we would rather write down now than discover later:

1. **Three web pages do not exist, and this blocks submission.** The app links to a Privacy Policy,
   Terms of Use and Support page. All three URLs currently return "page not found". Apple checks the
   privacy policy link *automatically, as part of the submission form*, before any human looks at
   the app — so a broken link costs us a full review cycle, which is 24–48 hours we do not have
   spare against a 5 September deadline. **This is a human task, not a code task.** Someone needs to
   publish three simple pages and confirm they load.

2. **The demo blacks out one word it shouldn't.** The sample payslip is titled "Salary Slip — August
   2026", and iOS's name-detector is confident that "August" is a person's name. So the demo puts a
   bar over the month. It is over-caution, not a leak — nothing private is exposed — and the user can
   switch it off in one tap, but it looks slightly silly in a screenshot. We left it deliberately:
   teaching the app to ignore month names risks missing people actually named August, and that trade
   deserves a considered decision rather than a quick patch during a bug fix.

3. **Several pieces are waiting for independent sign-off.** Our process forbids anyone approving
   their own work. The person who fixed the leak is not allowed to declare the fix verified, so the
   detection, editor and export components are all sitting one review pass short of confirmed.

4. **Accessibility has not been driven on a real device.** Everything is built for it — labels on
   every control, an alternative list for people who cannot tap tiny boxes, a reduced-motion path —
   but "built for it" and "confirmed working with the screen reader turned on" are different claims,
   and we only make the ones we have evidence for.

## What this unlocks commercially

The app is now demonstrable. That matters more than it sounds:

- **The hackathon submission needs a demo video.** There is now something to film.
- **The next phase is the money.** Subscriptions, the paywall, and the free-tier limit already have
  their hook points wired in — the app already knows how to say "you've used your three free
  documents this month" and where to send you next. Nothing about payments has been built yet, and
  nothing about payments leaked into the rest of the code, which is exactly the state we wanted to
  be in before starting.
- **The "No Data Collected" claim survived the phase.** Five new screens, three ways to import a
  document, a library, and a share sheet — and still zero network connections anywhere in the app.
  That is checked automatically on every single build. It remains our strongest and least copyable
  marketing asset.

## How to explain this phase in thirty seconds

> "Last month we had an engine with no car. Now the app works end to end: photograph a document, it
> finds the personal details, you approve them, you get a clean file. And we caught something big —
> our automated tests said the redaction was perfect, but when someone actually opened the exported
> file and looked at it, the first digit of every ID number was still visible. Text-recognition
> can't see a single stranded character, so every text-based test in the world was blind to it. We
> rebuilt the check to count pixels instead of reading words. That's the difference between claiming
> your product is secure and knowing it."

**Related:** [[phase-2-technical]] · [[phase-2-guide-for-kids]] · [[phase-1-non-technical]] ·
[[DEC-001-app-concept]] · [[DEC-004-no-network]] · [[legal-urls-not-published]] · [[memory-index]]
