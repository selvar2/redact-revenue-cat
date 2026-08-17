---
id: phase-1-non-technical
date: 2026-08-17
phase: 1
audience: colleagues, management, non-engineers
tags: [phase-1, product, commercial, plain-language]
status: complete
---

# Phase 1 — What We Built, and Why It Matters

> For anyone who needs to explain this product without writing code.
> Siblings: [[phase-1-technical]] (for engineers) · [[phase-1-guide-for-kids]] (for a ten-year-old).
> No prior knowledge assumed. Every technical word is defined the first time it appears.

## The product in one paragraph

**Redact** is an iPhone and iPad app. You point it at a document — a photo of your passport, a bank
statement, a rental agreement, an invoice — and it finds the personal details inside it: names,
phone numbers, email addresses, card numbers, Indian ID numbers like PAN and Aadhaar. Then it
**permanently destroys** those details and gives you back a clean copy you can safely send to
anyone. Everything happens on your own phone. Nothing is ever uploaded anywhere.

## The problem we are solving

People are asked to share documents constantly. A landlord wants proof of income. An employer wants
ID. A support agent wants a copy of a bill. Almost every one of those documents contains far more
information than the person asking actually needs — and once you send it, you cannot get it back.

The usual workaround is to cover the sensitive bits with a black box before sending. This is where
things go badly wrong.

## Why "a black box over the text" is dangerous

Here is the single most important idea in this whole document, and it is not obvious.

A digital document is not a picture of words. It is a **stack of layers** — a bit like a sandwich.
The text sits on one layer. When you draw a black rectangle over it in Preview, Acrobat, Markup, or
almost any everyday tool, you are adding a *new layer on top*. You have not touched the text. It is
still sitting there underneath, complete and intact.

```
  What you see                 What is actually in the file
  ─────────────                ────────────────────────────
  ┌───────────────┐            ┌───────────────┐  ← black rectangle (a separate layer)
  │  Name: ███████│            ├───────────────┤
  │  PAN:  ███████│            │  Name: Priya  │  ← the original text, untouched
  └───────────────┘            │  PAN: ABCDE1234F
                               └───────────────┘
```

Anyone who receives that file can get the text back in seconds. They do not need hacking skills.
Three separate methods work:

1. **Select and copy.** Drag the cursor across the black box and paste it somewhere. The words
   appear.
2. **Delete the rectangle.** It is a separate object in the file. Click it, press delete.
3. **Extract the text.** A free, decades-old command-line tool called `pdftotext` dumps every word
   in a document, ignoring anything drawn on top.

This is not a theoretical risk. It is one of the most reliably repeated document-security failures
there is: sealed court filings, redacted legal settlements, and government reports have all leaked
this way, and they leaked because everyone involved believed the black box was doing something it
was never doing.

A second, quieter version of the same problem: **pixelation and blurring.** They look secure and are
not. Blurring is a mathematical operation applied to the original pixels, which means the original
pixels are still in the file, just scrambled in a predictable way. For short pieces of text drawn
from a known set of characters — a card number, a licence plate, an ID code — an attacker can
generate every possible candidate, blur each one the same way, and see which one matches. This has
been done in the real world. We therefore refuse to offer blur or pixelation at all, which is worth
saying out loud because it is a feature customers will ask for by name.

## What makes ours different

Redact never draws anything on top of anything. It **rebuilds the file from scratch**.

The app takes the picture apart into its individual coloured dots, **overwrites** the dots covering
the sensitive text with solid black — replacing them, not painting over them — and then writes a
brand-new file from those dots. The original text was never copied into the new file. There is no
layer to peel off, because there are no layers. There is nothing underneath, because there is no
underneath.

For PDFs with multiple pages, any page you redact is completely rebuilt this way. There is a real
cost to this, and we chose it deliberately: on a rebuilt page you can no longer select or copy the
*other* text either, because the whole page is now a picture. We accepted that trade. Losing the
ability to copy-paste is a cost you can see and understand. Leaving recoverable personal
information is a cost you cannot see until it has already hurt you. Pages you did not redact are
left alone and keep their selectable text.

### We also strip the invisible information

Every photo your phone takes carries a hidden block of data alongside the image: when it was taken,
which device took it, the lens, and — routinely — the **GPS coordinates of exactly where you were
standing**. PDFs carry an equivalent: author name, the software used, creation and modification
dates.

A redacted document that still carries that hidden block is arguably *more* dangerous than an
un-redacted one, because the user now believes the file is safe. Redact removes all of it. Not by
going through a checklist of things to delete — that approach silently goes out of date the moment
Apple adds a new field — but by building the new file from the picture alone and never copying the
hidden block across in the first place.

### And we prove it, rather than claiming it

This is the part that matters commercially, and it is genuinely unusual.

Most apps in this category assert that they are secure. We have an automated test that behaves like
an attacker. Every single time the code changes, the test:

1. Creates a document containing a known secret code (`ABCDE1234F`), complete with fake GPS
   coordinates attached.
2. Runs it through the real, shipping redaction path — not a simplified test version.
3. Attacks the result. It runs the phone's own text-recognition engine over the output, the way
   someone trying to recover the text would. It runs the text-extraction attack on PDFs.
4. **Fails the build** if the secret comes back.

There is a further layer of rigour that most teams skip. The test also builds two deliberately
*broken* versions — one with a semi-transparent black box, one with the classic PDF rectangle-on-top
— and checks that those **do** leak. If the broken versions ever stop leaking, it means our attack
tools have gone blind, and every "the secret is gone" result would be meaningless. So the test
proves not only that our redaction works, but that the test itself is still capable of noticing if
it stopped.

It also checks the opposite failure: text *outside* the redacted area must survive. A tool that
destroys the entire page is trivially secure and completely useless.

## What was actually delivered this phase

Four pieces of foundation, built in parallel by four separate agents and then independently
reviewed:

| Piece | In plain terms |
|---|---|
| **Design system** | The app's visual vocabulary — every colour, size, spacing, and animation defined once and reused. Dark navy with a violet-to-amber gradient and frosted-glass panels. |
| **Detection engine** | The part that reads the document and works out which bits are personal information. |
| **Redaction core** | The part that destroys them. |
| **Storage layer** | Keeps your documents on your device, and genuinely deletes them when you say delete. |

### On detection: why we check, not just guess

Finding "a 12-digit number" in a document is easy and nearly useless — invoice totals and order
numbers are also 12-digit numbers. If the app blacks out random numbers, users lose trust in the
review screen and start approving everything without looking, which is exactly how real personal
information ends up getting missed.

So for every ID format that has one, we run its **checksum** — a built-in mathematical
self-consistency test that the number's own designers included so that typos can be caught. Aadhaar
numbers, credit card numbers, and GST numbers each have one. A number that fails its checksum is
not that kind of ID, full stop. This is not a guess; it is arithmetic.

Where no checksum exists — names, places, phone numbers — the app is honest about it. Those appear
in the review list with lower confidence, as suggestions you can decline. The app never silently
pretends to be certain.

Everything runs using capabilities already built into iPhones. There is no AI service, no server, no
per-document cost to us, and no waiting.

### On storage: deletion that means deletion

When you delete a document, the app deletes the image files off the disk *first*, then removes the
database entry. That order is chosen on purpose. If the phone dies mid-operation, you are left with
a visible record whose files are gone — annoying but honest — rather than files that no record
points at, which nobody can see and which are, in a privacy app, an actual leak of content the user
believes is gone.

The app also excludes those files from iCloud and iTunes backups, so a restored phone cannot
resurrect a document you thought you had destroyed. And it sweeps for stray leftover files every
time it launches.

## Where the money comes from

The business model is a subscription, run through **RevenueCat** (the industry-standard service for
handling app subscriptions, and the sponsor of the hackathon this was built for).

- **Free tier:** 3 documents per month, single-page, image export only. Enough to solve a real
  problem occasionally, and enough to prove the app works before anyone pays.
- **Pro tier:** unlimited documents, multi-page PDFs, batch processing, custom detection rules, and
  an audit log recording what was removed from what.

The free tier is deliberately generous on *quality* and limited on *volume*. Someone redacting one
document a year should never pay us; someone redacting documents weekly — a landlord, a recruiter,
a freelancer sending invoices, an accountant, a paralegal — hits the ceiling quickly and gets
obvious value from lifting it.

### The commercial advantage most competitors cannot copy

The app makes **zero network connections**. None. No analytics, no crash reporting, no font
downloads, no telemetry. The one exception is the subscription service itself, which needs to know
whether you have paid.

That is a strict engineering rule, checked automatically on every build — not a promise in a privacy
policy. And it buys three things:

1. **A truthful "No Data Collected" label on the App Store.** Apple requires every app to declare
   what it collects, and that declaration appears on the store listing. For a privacy product, being
   able to answer "nothing" honestly is the single strongest marketing asset available, and it
   cannot be faked — Apple checks, and competitors who use analytics simply cannot claim it.
2. **A faster, calmer App Review.** Fewer moving parts means fewer grounds for rejection, which
   matters enormously against a fixed submission deadline.
3. **No running costs.** No servers, no per-document AI charges. Every subscription is close to pure
   margin, and the app cannot become unprofitable if it suddenly gets popular.

There is a fourth, subtler benefit: because nothing is uploaded, the app works on a plane, in a
basement, and in a country with a data-residency law. We are not asking anyone to trust us with
their passport. We never have it.

## Positioning, in one sentence each

- **Against free tools** (Preview, Markup, phone photo editors): those cover text up; we destroy it,
  and we can prove the difference with a test.
- **Against desktop professional tools:** those are expensive, desk-bound subscriptions; we are on
  the phone that took the photo, and there is no upload step.
- **Against cloud redaction services:** they need your document on their servers. We never see it.
- **Against pixelate/blur features in other apps:** those are reversible for short codes. We do not
  offer them, on purpose, and we say why.

## Honest status

This phase built the engine, not the car. There are no screens yet for scanning, editing, or
exporting — that is the next phase. What exists today is the machinery underneath, tested and
working: **79 automated tests, all passing** at the last recorded full run.

Three things are genuinely unfinished, and we would rather write them down than discover them later:

1. **One known gap in multi-page PDFs.** If someone imports a PDF that a *different* tool already
   "redacted" badly — with the fake black box described earlier — and then uses Redact on a
   different page, we currently pass that bad page through untouched, fake black box and all. We
   never create that problem, but we can inherit it. Fixing it requires a product decision, because
   every option has a real cost: flattening every page destroys copy-paste on pages the user never
   touched; silently deleting boxes would also delete legitimate comments and signatures; warning
   the user is the honest answer but needs the export screen that does not exist yet. **Recommended
   answer:** when the export screen is built, detect these pages and let the user knowingly choose
   to flatten them.
2. **An advanced iOS 26 feature is a placeholder.** On the newest iPhones we intended to use Apple's
   on-device language model to judge ambiguous cases — is "Salem" a city or a surname? That code
   currently just runs the standard detection instead. It is labelled as such rather than pretended
   about. Nothing is broken; it is simply not yet smarter than the base version.
3. **Three of the four pieces are awaiting independent sign-off.** Our process forbids anyone from
   approving their own work. The pieces were built, reviewed, and the review findings fixed — but
   the fixer is not allowed to declare its own repairs verified. A fresh reviewer pass is the next
   step.

## How to explain this to someone in thirty seconds

> "Most apps 'redact' a document by drawing a black rectangle over the text. The text is still in
> the file underneath — you can copy it out, or just delete the rectangle. That is how sealed court
> documents have leaked. Redact rebuilds the file from scratch with the sensitive pixels
> overwritten, strips the hidden GPS and device data too, and does it all on your phone with nothing
> uploaded. And we have an automated test that tries to recover the secret from our own output and
> fails the build if it can."

**Related:** [[phase-1-technical]] · [[phase-1-guide-for-kids]] · [[DEC-001-app-concept]] ·
[[DEC-004-no-network]] · [[memory-index]]
