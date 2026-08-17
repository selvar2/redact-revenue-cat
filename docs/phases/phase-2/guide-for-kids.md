---
id: phase-2-guide-for-kids
date: 2026-08-17
phase: 2
audience: curious 10-year-olds (and anyone who likes a good explanation)
tags: [phase-2, explainer, kids]
status: complete
---

# Stickers, Paint, and the Bar That Missed by One Letter

> Siblings: [[phase-2-non-technical]] (for grown-ups at work) · [[phase-2-technical]] (for the
> people who write the code).
> The story so far: [[phase-1-guide-for-kids]].

## Where we got to last time

Last time we built the **machine**. It could find secrets in a picture and destroy them.

But it had no buttons. Nobody could use it. It was like building a brilliant engine and leaving it
sitting on the garage floor with no car around it — no steering wheel, no seats, no doors.

This time we built the car.

Now you can actually open the app on a phone, point it at a piece of paper, and watch it work. And
something went wrong in a really interesting way. That's the best part of this story, so hang on for
it.

## The most important idea in the whole app: stickers vs paint

Imagine you've got a drawing, and there's one word on it you want to hide.

**Way number one: a sticker.** You put a black sticker over the word. It looks hidden! But get a
fingernail under the edge, peel it off, and — hello — the word is still there. It was always there.
You never touched it. You just covered it.

**Way number two: paint.** You paint over the word with thick black paint. Now try to peel that off.
You can't. There's no edge to get under. The paint didn't cover the word — the paint *replaced* it.
The word is gone. Not hidden. **Gone.**

```
   STICKER                          PAINT
   ┌─────────────┐                  ┌─────────────┐
   │ Name: ▓▓▓▓▓ │  ← peel it...    │ Name: █████ │  ← peel it...
   └─────────────┘                  └─────────────┘
   ┌─────────────┐                  ┌─────────────┐
   │ Name: Ananya│  ← ...it's back  │ Name: █████ │  ← ...nothing. It's just black.
   └─────────────┘                  └─────────────┘
```

Here's the shocking bit: **almost every app on your computer that says it "hides" something is using
stickers.** Preview, Acrobat, the markup tool on your phone — sticker, sticker, sticker. They all
look exactly like paint on the screen. You cannot tell the difference by looking.

And this has caused real disasters. Actual court documents, ones that were supposed to keep people's
names secret, have been published with black boxes on them — and someone peeled the boxes off in
about four seconds and read every name.

**Our app is the paint one.** That's the whole point of it. That's why it exists.

## But wait — how does the app know *where* the word is?

Good question! Because a computer looking at a photo doesn't see words at all.

To a computer, a photo is a giant grid of coloured dots. Millions of them. Each dot is just three
numbers: how red, how green, how blue. That's the entire photo. No letters. No words. No meaning.

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

So the phone has a special helper called **OCR**, which stands for Optical Character Recognition —
a very fancy way of saying *"squinting at shapes and guessing letters."*

It's been shown millions and millions of examples of letters. Big ones, tiny ones, wobbly
handwritten ones, letters in shadow, letters photographed at a funny angle. Until it got really,
really good at going: *that blob is probably an "A". That one's an "8" and not a "B", because the
left side is closed up.*

And here's the treasure: OCR doesn't only say **what** the letters are. It says **where** they are.

Because if you know exactly where a secret is sitting on the page, you know exactly which dots to
paint over.

## What "scanning a document" actually means

When a grown-up says "scan this document", they mean: **turn a real, physical, floppy piece of paper
into a picture the computer can work with.**

Your phone camera can do it, but a plain photo is a bit rubbish for this. Think about what happens
when you photograph a page on a table:

- The page is at an angle, so it comes out as a wonky trapezium instead of a rectangle
- One corner is brighter than the other because of the lamp
- Your hand wobbled
- Half the picture is table

So iPhones have a proper **document scanner** built in. You hold the phone over the page and it
finds the four corners, then does something clever: it stretches the wonky shape back into a proper
rectangle, like ironing a crumpled shirt flat. Then it evens out the lighting so the paper looks
white all over.

```
   What the camera sees          What the scanner gives back

        ╱‾‾‾‾‾‾‾╲                    ┌───────────┐
       ╱  wonky   ╲       ───►       │   flat    │
      ╱   page     ╲                 │   page    │
     ╱_____________╲                 └───────────┘
     (dark in one corner)            (evenly lit, square)
```

That flat, even picture is what OCR reads. Give OCR the wonky one and it makes far more mistakes —
and in our app, a mistake means a secret doesn't get painted over.

Our app also lets you bring in a picture you already took, or a PDF (which is just a document format
that can hold lots of pages). PDFs get turned into pictures too — one picture per page — because
pictures are the thing we know how to paint on.

## The scanner line (the pretty bit)

When you open a page in our app, a glowing purple-to-orange line sweeps down it, like a photocopier.
As it passes over each secret, that secret's box pops into view. When it reaches the bottom, all the
black bars slam down at once and the phone gives one little buzz.

Here's the neat trick. You'd think there's a stopwatch for each box: *"box one, appear after 0.3
seconds; box two, after 0.5 seconds..."* Nope. That would be a nightmare — you'd have to redo all
the timings whenever anything moved.

Instead, **each box just watches the line.** Every box knows how far down the page it lives — say,
40% of the way down. And there's one number that counts smoothly from 0 to 1 as the line travels.
Each box asks, over and over: *has that number passed my number yet?* When it has, the box appears.

One counter. Every box checks it. They light up in perfect order automatically, top to bottom,
without a single stopwatch. If you add a new box halfway through the sweep, it still behaves
perfectly, because it's asking the same question as everyone else.

```
     0.0 ──────────────────────► 1.0
      │
      ├─ 0.2  box A says "yep, passed me"   ✔ appears
      ├─ 0.4  box B says "yep"              ✔ appears
      ├─ 0.7  box C: "not yet..."
      └─ 0.9  box D: "not yet..."
```

Oh — and one more thing we care about a lot. Some people get dizzy or feel sick from things sliding
around on screens. Phones have a setting for that called *Reduce Motion*. If you've turned it on,
our app skips the sweep entirely and just gently fades everything in. **And the buzz doesn't happen
either.** If someone has specifically asked the phone to calm down, buzzing their hand would be a
pretty rude way of being "accessible".

## Now the good bit: the day we were wrong

Everything was finished. Every single test passed — 86 of them. The app opened, worked, and made a
nice clean file. Job done. Time for cake.

Then someone did the boring, unglamorous thing. They didn't look at the app's screen. They dug the
actual finished file out of the phone's storage, blew it up huge, and **looked at it with their own
eyes.**

```
   Employee   Ananya Mehra          ← no bar at all! Her name is just... sitting there.
   Date of Birth: 1███████          ← the "1" escaped
   IFSC: Z███████                   ← the "Z" escaped
```

And the app was cheerfully saying above it: *"10 items removed. There's nothing left to recover."*

Oof.

Two completely different things had gone wrong at the same time, which is why it looked so
confusing.

### Mistake one: the name-finder had never seen a form

The bit of the phone that spots people's names learned by reading **sentences**. Millions of them.
Things like *"Ananya Mehra went to the shop."* In a sentence, there are loads of clues: the name is
at the start, it's followed by a doing-word, it's got a capital letter in the right place.

But a form isn't a sentence! A form is a list:

```
      Employee          Ananya Mehra
      Employee ID       NWA-2291
      Designation       Senior Data Analyst
```

There's no sentence anywhere. So the name-finder shrugged and said "nothing here." It genuinely
found *nothing*.

Our fix was to stop being clever and start being obvious: **read the label.** If a document has the
word "Employee" printed next to something, then that something is very probably an employee's name.
You don't need a fancy language brain for that. You just need to read the sign.

The lovely thing is that this works in *any* language. A name-guessing brain trained on English
sentences is hopeless with a form in Tamil or Polish. But a printed label sitting next to a value is
a label in every language on Earth.

### Mistake two: the bars were sliding to the right

This one is beautiful, in a slightly annoying way.

The app knew where a whole *line* of text was — say, `Date of Birth: 14/03/1994`. But it needed just
the date bit at the end. So how did it work out where that bit started?

It counted letters. `Date of Birth: ` is 15 characters long, the whole line is 25 characters, so the
date must start 15/25ths — 60% — of the way along. Sensible! And wrong.

Because letters **aren't all the same width**:

```
   Wide letters:   W  M  O  @
   Skinny letters: i  l  .  1
```

Look at the word `Mill`. That "M" is enormous. Those two "l"s are practically hairs. If you count
them as four equal letters you'll guess completely the wrong place.

So all our bars were drifting a bit to the right, and the very first character of each secret was
poking out at the left edge. Just one character. Which sounds harmless!

It isn't. If you're trying to guess someone's date of birth and you already know it starts with a 1,
you've just deleted more than half the possibilities. One character is a *huge* head start.

The fix: stop guessing. Ask the phone's text engine to measure each letter individually and tell us
exactly where each one is. It can do that! We just weren't asking.

### And then we made it much worse

Ha. Yes.

The very first version of the fix asked the text engine to measure **every** character, one by one.
Including the spaces.

Turns out that when you ask "where is this space?", the text engine doesn't say "that's a silly
question, spaces are invisible." It confidently returns a box the size of half the page.

And every single ID number on our test document has a space in it.

So the app drew a black bar over the entire top half of the page. Extremely secure! Completely
useless. (This is a classic programming feeling: you fix a bug, and the bug you get instead is
*bigger*. It's normal. It means you're getting closer.)

Now we never ask about spaces, and we also throw away any measurement that lands somewhere silly —
outside the line of text it was supposed to come from.

## The test that could see what nobody else could

Here's the really clever part, and it's the thing the whole team learned this phase.

Our tests worked by **attacking our own output**. The test would make a file, redact it, then run
OCR over it and shout if it could still read the secret. That's a great test. It behaves like a
real burglar.

But when the engineer wrote a new test for this exact bug... **it passed on the broken version.**

Why? Because OCR is a *reader*. It reads words. And a single lonely "1" stranded next to a big black
bar isn't a word. OCR looks at it, decides it's a smudge or a bit of the bar, and ignores it. So a
file that clearly, visibly says `Date of Birth: 1` gets reported back as `Date of Birth:` —
completely clean.

**The reader was blind to exactly the leak that mattered.**

So the new test stopped reading. It **counts colours** instead.

It asks the phone to measure precisely where a secret sits in the *original* picture. Then it looks
at that exact same patch in the *finished* file and asks one simple question:

> How many different colours are in here?

If the answer is **1** — pure black, nothing but black — the secret is properly gone. If the answer
is 6, there's something in there. Something with edges. Something shaped like a "1".

```
  Broken version, that patch:      Fixed version, that patch:

    █ █ █ ░ █ █ █ █                  █ █ █ █ █ █ █ █
    █ █ ░ ░ █ █ █ █                  █ █ █ █ █ █ █ █
    █ █ █ ░ █ █ █ █                  █ █ █ █ █ █ █ █
    → 6 different colours            → 1 colour
    → FAIL                           → PASS
```

No reading involved. No guessing. Just: *is this rectangle one flat colour, or isn't it?*

### And then they checked the test itself

This is my favourite bit, and it's a habit worth stealing for absolutely anything you ever make.

After writing the new test and watching it pass, the engineer **deliberately put the bug back in**
— and ran the test again to check it *failed*.

Why on earth would you do that? Because a test that always says "everything's fine" is worse than
having no test at all. A useless smoke alarm is worse than no smoke alarm, because you stop
checking for smoke yourself. You have to hold a match under it once in a while to know it still
works.

Test failed with the bug in. Test passed with the bug out. **Now** you can trust it.

## Things that still aren't right

Honest list. Grown-up engineers write these too, and the good ones write them down instead of
quietly hoping nobody notices.

**The app blacks out a month.** Our practice document says "Salary Slip — August 2026" at the top.
The name-finder is *absolutely convinced* that "August" is a person's name. So the app puts a black
bar over the month, which looks a bit daft.

We left it alone on purpose, and the reason is genuinely interesting: some people really *are* named
August. If we teach the app "months are never names", we'd be protecting the app's dignity by
risking a real person's actual name getting through. Being too careful is embarrassing. Not being
careful enough is dangerous. When those two are in tension, you pick embarrassing — and you write
the trade down so a human can decide properly later.

**Three web pages don't exist yet.** The app has links to a Privacy Policy, Terms of Use and a
Support page — and right now all three go to a "page not found" error. Apple checks those links
automatically before a human even opens the app, so this has to be sorted before we can publish.
Nobody can fix that with code. A person has to go and write three web pages.

**Some parts are waiting for a second opinion.** We have a strict rule: **you're not allowed to mark
your own homework.** The person who fixed the bars isn't allowed to be the person who declares them
fixed. Someone else has to look, with fresh eyes, and agree.

That rule is annoying. It's also exactly the rule that caught the leak in the first place.

## The one thing to remember

If you take one idea away from all of this, take this one:

> **The test passed, the build was green, the screen said "nothing left to recover" — and it was
> still leaking.**
>
> Somebody had to go and *look at the actual thing*, with their actual eyes, to find out.

Green ticks are lovely. But a green tick only means "the checks we thought of all passed." It never
means "there's nothing wrong."

Go and look at the real thing. Every time.

**Related:** [[phase-2-non-technical]] · [[phase-2-technical]] · [[phase-1-guide-for-kids]] ·
[[memory-index]]
