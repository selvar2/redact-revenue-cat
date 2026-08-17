---
id: phase-1-guide-for-kids
date: 2026-08-17
phase: 1
audience: curious 10-year-olds (and anyone who likes a good explanation)
tags: [phase-1, explainer, kids]
status: complete
---

# The App That Colours Out Secrets — And Can't Be Undone

> Siblings: [[phase-1-non-technical]] (for grown-ups at work) · [[phase-1-technical]] (for the
> people who write the code).

## Start with a puzzle

Imagine your friend asks to borrow your school report — but only to see your art grade. The report
also has your home address, your birthday, and your parents' phone numbers on it.

You want to show one thing and hide the rest. So you grab a black marker and cross the private bits
out.

Now here's the puzzle: **did you actually hide them?**

If you used a real marker on real paper — yes. The ink soaked into the paper. Those letters are
gone forever. You could hold the page up to the sun and see nothing.

But if you did it on a computer... maybe not. And *why* not is the whole story of this app.

## First: what even is a computer program?

A computer is fantastically fast and completely clueless. It can do billions of tiny things every
second, but it doesn't know what any of them mean. It has no ideas. It just follows instructions.

A **program** is a list of instructions, written down so precisely that a clueless thing can follow
it without ever asking "wait, what did you mean?"

It's like writing instructions for making toast — except you have to write them for someone who has
never seen bread, doesn't know what "brown" is, and will take everything absolutely literally:

```
1. Pick up ONE slice of bread.
2. Put it in the slot on the top of the toaster.
3. Push the lever down until it clicks.
4. Wait. When the lever pops back up, the bread is toast.
5. Take it out. It is hot. Do not squeeze it.
```

Miss step 5 and your computer will happily hold hot toast forever. It doesn't mind. It doesn't know.

Our app, **Redact**, is a big pile of instructions like that. And because a computer follows them
*exactly* every single time, it's brilliant at boring, careful jobs — like checking every single
line of a document for a phone number, without ever getting distracted or tired.

## Second: how does a program "see" words in a photo?

Here's something strange. When you take a photo of a page of writing, the computer doesn't see
words. It doesn't see letters. It doesn't see *anything*.

A photo, to a computer, is just a giant grid of coloured dots. Millions of them. Each dot is a
number saying how red, how green, and how blue it is. That's it. That's the whole photo.

```
Your eye sees:              The computer stores:

    C A T                   . . . . . . . . . . . .
                            . ■ ■ . . ■ . . ■ . ■ .
                            ■ . . . . ■ ■ ■ . ■ ■ .
                            ■ . . . . ■ . ■ . ■ . ■
                            . ■ ■ . . ■ . ■ . ■ . ■
                            . . . . . . . . . . . .
                            (just dark dots and light dots)
```

So how does it read? There's a clever piece of the iPhone called **OCR** — it stands for Optical
Character Recognition, which is a fancy way of saying **"looking at shapes and guessing letters."**

It has been shown millions of examples of letters — big ones, small ones, wobbly handwritten ones,
letters in shadow, letters photographed at an angle — until it got extremely good at going: *that
blob is probably an "A". That one's an "8", not a "B", because the left side is closed.*

And here's the important bit for us: OCR doesn't just say **what** the letters are. It says
**where** they are — "the word 'Priya' is at this exact spot, this many dots across and this many
dots down."

That "where" is the treasure. Because if you know exactly where a secret is sitting, you know
exactly which dots to destroy.

## Third: finding which words are actually secret

Now the app has all the words on the page. But most of them aren't secret! "Invoice", "Total",
"Thank you for your custom" — nobody minds if you see those.

So the app plays a kind of detective game, and it uses two different kinds of clues.

### Clue type 1: shapes it can be *certain* about

Some kinds of secret information have a very particular shape. In India, a **PAN card** number is
always five letters, then four numbers, then one letter. Like `ABCDE1234F`. Always. Every single
one.

So the app looks for that shape. Easy!

Except... not so easy. Because some ID numbers are just twelve digits long — and so are lots of
completely boring numbers. An invoice total. An order number. A row of prices squished together.

If the app blacked out every twelve-digit number, it would black out half the page for no reason.
And here's the sneaky problem with that: if the app cries wolf too often, people stop reading its
suggestions and just tap "yes, yes, yes" without looking. And *that's* when a real secret slips
through. Being wrong too often is its own kind of dangerous.

So for the important IDs, the app uses a genuinely brilliant trick: a **checksum**.

### The checksum: a number that checks itself

The people who invented these ID numbers were clever. They made the **last digit a secret test** for
all the others.

Here's a tiny pretend version. Say a valid code is four digits, and the rule is: *the last digit
must be the first three added together, keeping only the final digit of the answer.*

```
  4 1 2 ?      →  4 + 1 + 2 = 7   →  the code must be 4127 ✓

  4 1 2 9      →  4 + 1 + 2 = 7,  but it says 9        ✗  NOT a real code
```

So `4127` is a real code and `4129` isn't — and you can tell **without knowing anything about who it
belongs to.** You just do the sum.

Real checksums are more complicated than adding up (the one for Aadhaar numbers uses a beautiful bit
of maths about rotating and flipping a five-pointed star, which is a rabbit hole worth falling down
one day). But the idea is exactly the same: **the number proves itself.**

This means when our app says "this is an ID number", it isn't guessing. It did the arithmetic.
Random invoice totals almost never pass the test by accident.

### Clue type 2: things it has to guess about

Names are harder. There's no shape rule for a name. And it gets genuinely tricky — "Salem" is a city
in India *and* it's somebody's surname. Even a human would need to look at the rest of the page to
decide.

So the app makes its best guess and — this is the honest part — it **says** it's a guess. Certain
things and guesses go in a list you can look through, and you get the final say. You can tap
anything to add it, or tap a guess to say "no, leave that one."

The computer does the boring, careful work. You do the deciding. That's a good partnership.

## Fourth: the marker that can't be peeled off

Now the big idea. This is the bit that makes our app different from almost everything else.

Remember how a photo is just a grid of coloured dots? Well, a document on a computer is often more
like a **sandwich of see-through sheets** stacked on top of each other. The words are on one sheet.
A picture might be on another.

When most apps "hide" something, they slide a **new sheet on top** with a black rectangle drawn on
it.

```
  What you see:              What's really in the file:

  ┌──────────────┐            ┌──────────────┐ ← sheet 3: a black rectangle
  │ Name: ██████ │            ├──────────────┤ ← sheet 2: nothing here
  │ PAN:  ██████ │            │ Name: Priya  │ ← sheet 1: the words. Still there!
  └──────────────┘            │ PAN: ABCDE1234F
                              └──────────────┘
```

Looks perfect. Feels safe. **It isn't.**

Because anyone who gets that file can just... lift the top sheet off. Click the black rectangle,
press delete, and read what's underneath. Or drag their mouse across the black box, copy, and paste
it somewhere. The words come right out.

It's a sticker, not a marker. And a sticker can always be peeled off. 🏷️

This has happened for real, to grown-ups whose whole job is being careful — lawyers, governments,
newspapers. They sent out documents they were *certain* were safe, and people peeled the stickers
off. Secrets got out. Not because anyone was a genius hacker, but because a sticker is a sticker.

### So what do we do instead?

We don't use a sticker. We don't use a top sheet at all.

**We go into the grid of dots and change the actual dots.**

Every dot where the secret was — we take it out and put a black dot in its place. Not a black dot
*over* it. *Instead* of it. The old dot is thrown away and never written down again.

```
   Before:   . . ▓ ▓ . ▓ . ▓ ▓ ▓ . .     ← dots that make up "ABCDE1234F"
                    ↓  we replace them, we don't cover them  ↓
   After:    . . ■ ■ ■ ■ ■ ■ ■ ■ ■ .     ← all identical black. Nothing else.
```

Then we build a **brand new file** out of the new dots.

Think about what that means. There's no sheet to lift, because there are no sheets. There's nothing
underneath, because there **is** no underneath. The secret didn't get hidden. It stopped existing.

It's a real marker, on real paper. It soaked in. 🖊️

### Two extra things we're careful about

**No see-through markers.** If you make black 99% dark instead of 100% dark, a tiny ghost of the
letters is still there — too faint for you to see, but a computer can turn the brightness way up and
read it. So our black is *completely* black, and the app won't even let a programmer make it
slightly see-through by accident. That option doesn't exist.

**No blurring.** Blurring looks like a great way to hide something, and it is a trap. Blurring is a
recipe — take each dot, mix it with its neighbours in a specific way. And any recipe can be run
backwards. If you know the secret is ten characters long, a computer can write out every possible
ten-character code, blur each one with the same recipe, and see which one comes out matching. It's
like recognising a friend through frosted glass: you can't read them, but you can compare shapes
until one fits. So we don't offer blur. On purpose. Even though people ask for it.

## Fifth: the invisible secrets you didn't know were there

Here's one that surprises most grown-ups.

When your phone takes a photo, it tucks a little hidden note inside the file. Not in the picture —
*next to* it. The note says things like:

- 📅 the exact date and time
- 📱 which phone took it
- 📍 **the GPS location — the precise spot on Earth where you were standing**

You've never seen this note. But it's in nearly every photo you've ever taken, and anyone who
receives the photo can read it.

So imagine: you carefully black out your address on a photo of a letter — and then send a file that
quietly says "taken at 12.9716°N, 77.5946°E", which *is* your address, just written in numbers.
You'd have hidden your secret and handed it over at the same time.

Our app throws that note away completely. And it does it in a clever way. Instead of going through a
checklist — *delete the date, delete the location, delete the phone name* — which would go
out-of-date the moment phones start saving something new, we simply **build the new file out of the
dots and nothing else.** The note is never copied across, because we never pick it up in the first
place.

If you never carry it, you can never drop it.

## Sixth: how do we KNOW it works? We attack ourselves.

This is my favourite part.

Saying "our app is safe" is easy. Anyone can say that. So we made the app prove it — over and over,
automatically, forever.

Every single time anyone changes even one line of the app's instructions, a robot test wakes up and
does this:

```
   1. 📄  Make a fake document with a secret code in it: ABCDE1234F
          (and stick a fake GPS location on it too)
                          ↓
   2. 🖊️  Run it through the app's real redaction — the exact same one you'd use
                          ↓
   3. 🔍  ATTACK IT. Use the phone's OCR to try to read the secret back.
          Use the text-copying trick on PDFs. Try everything an attacker would.
                          ↓
   4. ❓  Did the secret come back?
          YES → 🚨 STOP EVERYTHING. The app is broken. Nobody ships anything.
          NO  → ✅ Good. Carry on.
```

If the secret ever escapes, the whole thing grinds to a halt until it's fixed. Not a warning. A
full stop.

### But wait — how do we know the test isn't broken?

Brilliant question, and it's the one most people forget to ask.

Imagine our attack tool quietly stopped working — it can't read *anything* any more. It would look
at our redacted file, find no secret, and cheerfully announce "PASSED!" every single time. Even if
the app had completely fallen apart.

A test that can never fail is worse than no test. It doesn't just tell you nothing — it tells you
something comforting and wrong.

So the test also builds **two deliberately rubbish versions** of redaction:

- one with a see-through black box (the ghost-letters trick)
- one with the peel-off sticker on a PDF

and then checks that it **CAN** read the secret out of both of them. Those two tests *want* to find
the secret. They fail if they don't.

So every time the app is tested, we learn two things at once:

> ✅ Our real redaction hides the secret
> ✅ Our attack tool can still find secrets, so the first result actually means something

It's like testing a smoke alarm by pressing the button. You're not hoping for silence. You want to
hear it scream — because that's how you know it'll scream when it matters. 🔔

### One more check: don't destroy too much!

There's a silly way to make a document perfectly safe: black out the *entire page*. Nothing can
leak. Total success!

Except it's completely useless. Nobody can read anything.

So the test also puts some ordinary, not-secret words on the fake document — and checks those are
**still readable** afterwards. The app must destroy exactly the right amount: everything secret,
nothing else.

Being safe isn't enough. It has to be safe *and* useful.

## Right now, what's finished and what isn't

Grown-ups sometimes only tell you the good bits. Here's everything.

**Working:** the reading, the detecting, the checksum maths, the dot-destroying, the invisible-note
removal, the saving-and-really-deleting, and all the app's colours and shapes. **79 robot tests, all
passing.**

**Not finished yet:**

- 🖼️ **There are no buttons yet.** Seriously! The engine runs beautifully but there's no screen to
  press. That's like having a brilliant engine with no steering wheel or seats. That's the next
  job.
- 📎 **One tricky leftover.** If somebody gives us a document that a *different* app already put
  fake peel-off stickers on, and you only fix page 1, we hand page 3 back with its dodgy sticker
  still attached. We never make that mistake ourselves — we can only inherit it from someone else's
  work. The tricky part is deciding what to do: flatten *every* page (safe, but then you can't copy
  text from pages you never touched), quietly delete all stickers (but some stickers are real
  notes and signatures that people want!), or warn you and let you choose. The last one is the best
  answer, and it needs the buttons that don't exist yet. So it's written down in big letters where
  nobody can forget it.
- 🤖 **A clever brain that's still asleep.** The very newest iPhones have a small AI built in, and
  we want to use it for the genuinely hard calls — is "Salem" a city or a person? The slot for it
  is built, but it isn't switched on yet, because nobody could confirm exactly how to talk to it,
  and guessing would have broken everything else. So instead of pretending, we wrote down "this
  isn't done yet" and moved on. That's allowed. That's *good*, actually.
- 🔍 **Somebody else still has to check three of the four pieces.** There's a rule on this project:
  **you're not allowed to mark your own homework.** The person who fixes the problems can't be the
  person who says "yep, all fixed." Someone with fresh eyes has to look.

## Now you can explain it to a friend

If someone asks what this app does, here's everything you need:

> "Most apps hide secrets on a document by putting a black sticker over the words. But the words are
> still underneath — you can peel the sticker off and read them. That's really how secrets have
> leaked from lawyers and governments.
>
> This app doesn't use a sticker. It goes into the picture and swaps out the actual coloured dots
> for black ones, then builds a whole new file. There's nothing underneath to find, because there's
> no underneath.
>
> It also throws away the invisible note your phone hides in every photo — the one with the GPS
> location of where you were standing.
>
> And there's a robot that tries to steal the secret back from the app's own work every single day.
> If it ever succeeds, everything stops until it's fixed."

That's it. That's the whole thing. 🎉

**Related:** [[phase-1-non-technical]] · [[phase-1-technical]] · [[memory-index]]
