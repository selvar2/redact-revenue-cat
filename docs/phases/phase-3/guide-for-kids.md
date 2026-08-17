---
id: phase-3-guide-for-kids
date: 2026-08-17
phase: 3
audience: curious 10-year-olds (and anyone who likes a good explanation)
tags: [phase-3, explainer, kids, money, subscriptions]
status: complete
---

# The Shop Inside the App, and the Person at the Door Who Remembers You

> Siblings: [[phase-3-non-technical]] (for grown-ups at work) · [[phase-3-technical]] (for the
> people who write the code).
> The story so far: [[phase-2-guide-for-kids]].

## Where we got to last time

We built a machine that finds secrets in a picture and **destroys** them — really destroys them,
paint not stickers. Then we built the app around it so a person could actually use it: point a phone
at a piece of paper, tap a few times, done.

There was one thing missing. The app was free. Completely, entirely free, forever.

That's lovely, but somebody has to eat. This time we built the part where the app can ask for money.

And it turns out that's a much stranger thing than it sounds.

## First: what does "buying something inside an app" even mean?

Here's the confusing bit. When you buy a bicycle, you get a bicycle. It's *there*. You can sit on it.

When you buy something inside an app, nothing arrives. No box. No delivery van. Nothing gets heavier.

So what did you actually buy?

**You bought permission.**

Think about a swimming pool with a small pool everyone can use and a big pool with a diving board.
You pay, and someone gives you a wristband. The wristband isn't the thing you bought — you bought
*being allowed into the big pool*. The wristband is just how the lifeguard knows.

That's exactly what happens in Redact. The app already contains everything. The multi-page bit, the
custom rules, the whole lot — it's all sitting right there on your phone the moment you download it.
Paying doesn't send you anything new. Paying flips a switch that says **"this person is allowed."**

Programmers have a word for the wristband. They call it an **entitlement**. Ours is called `pro`.
Slightly disappointing word for such a fancy idea, but there it is.

## Now the strange part: the app isn't allowed to take your money

You'd think this would be simple. You tap "Buy", the app takes your money, done.

Nope. **The app is not allowed to touch your money at all.** Not even a little bit. If we tried,
Apple would refuse to let Redact into the App Store.

That sounds unfair for about ten seconds, and then you think about it properly and realise it's
brilliant.

### Imagine a giant shopping centre

Apple's App Store is a shopping centre with about two million shops in it, and Redact is one very
small stall near the back.

Now imagine every single stall could take your bank card directly. Two million strangers, each one
with their own little card machine, each one promising to be careful with your details. How many of
them would be careful? How many of them even *exist* next week?

So the shopping centre has a rule. There's **one till, at the front, run by the centre itself**. If
you want to buy something from any stall, you pay the centre. The centre takes the money, checks
everything, and then tells the stall: *"That one's paid. Let them in."*

The stallholder — us — never sees your card. Never knows your name. We just get a message saying
"paid", and we open the gate.

### What the shopping centre does for its cut

The centre keeps a slice of every sale. For a small stall like ours, it's **15 pence out of every
pound** — or 15 rupees out of every hundred. We keep the other 85.

That sounds like a lot until you write down what the centre actually does for it:

- It takes the money, safely, with a card machine we didn't have to buy.
- It handles the tax — and here's the mad part, *the tax in every country in the world*. Someone
  buys Redact in Brazil, and the right Brazilian tax gets paid without us learning a single word of
  Portuguese.
- If you want a refund, you ask the centre and the centre sorts it out.
- If someone's card gets stolen and used, that's the centre's problem, not ours.
- Every month, it takes everything we earned everywhere on Earth, adds it up, converts it into
  rupees, and sends one payment to a bank in India.

If we did all that ourselves, we'd need a whole company. Lawyers. Accountants. A person whose entire
job is answering the phone at three in the morning when the card machine breaks.

**15% for all of that is a bargain.** It genuinely is.

There's one more thing, and it's my favourite. Remember Redact's big promise — that your documents
never leave your phone and we never learn anything about you? That promise is only true because we
**have no computer anywhere that knows anything about you**. If we took the money ourselves, we'd
*have* to have one, with your name and your card in it. So not taking the money isn't just cheaper.
It's the reason we're allowed to make the promise at all.

## Then who remembers you paid?

Right. The centre took your money and told us you're allowed in. Fine. But:

- What if you delete the app and get it again next year?
- What if you get a new phone?
- What if you have an iPad *and* a phone?

We can't remember, because we don't keep a list of people. We just said that.

So we have a helper. It's called **RevenueCat**, and it's the person at the door with the guest list.

Here's the thing everyone gets wrong about RevenueCat: **no money ever goes near it.** Not a rupee,
not a penny. The money went to the shopping centre. RevenueCat is the doorkeeper who keeps a list of
who's on the guest list, and answers exactly one question, over and over, all day:

> *"Is this person allowed in?"*
> *"Yes."*

New phone? Still on the list. Deleted the app and came back? Still on the list. That's the whole job,
and it turns out to be exactly the job that's really annoying to do yourself.

RevenueCat does one more clever trick. The sales screen — the one with the prices and the buttons —
isn't really *inside* the app. It's more like a poster the doorkeeper holds up. Which means we can
change the poster whenever we like: new words, new colours, new pictures — and everybody sees the
new one immediately. If it were painted inside the app, changing one word would mean sending a whole
new version of the app to Apple and waiting two days for someone to check it.

We can even hold up **two different posters** — one to half the people, one to the other half — and
see which one people liked better. That's called an experiment, and it's a completely fair way of
finding out you were wrong about something.

## What's a subscription, then?

You'll have heard the word. It's on everything now. Here's what it actually means.

**Buying something once** is like buying a book. It costs money once, and it's yours. Forever. Read
it in ten years if you like.

**A subscription** is like a magazine that turns up every month. You keep paying, and it keeps
turning up. Stop paying, and it stops turning up. You're not really buying a *thing* — you're
renting *access*, one month at a time.

Redact offers three ways:

- **Monthly** — a small amount, every month, until you say stop. Cheapest to start, most expensive
  if you keep it for years.
- **Yearly** — pay once for twelve months. Costs more today, less per month. (We show you exactly
  how much less. And we *work it out* from the real prices instead of writing it down, so it can
  never accidentally be a lie.)
- **Lifetime** — pay once, ever, and it's yours like a book. Nothing renews. Nothing to cancel.

### The bit grown-ups get cross about

The thing about subscriptions is that they keep taking money **even when you forget about them**.
That's how loads of companies make their money — from people who signed up once and never noticed
again.

Apple made a rule about this, and it's a good rule. On the screen where you pay, the app **must**
tell you, in words you can read, three things:

1. exactly how much it costs,
2. exactly how often you'll be charged,
3. that it will **keep charging you automatically** until you stop it — and how to stop it.

Not hidden in the small print. Not in a menu somewhere. Right there, on the button screen.

Our app does this, and we made one strict rule for ourselves about it: **that sentence is never
allowed to be cut off.** If someone has their text size turned way up because they can't see well,
the sentence gets taller and pushes everything else down. It never turns into "Renews automatically
until…" with the important half missing. That would be the sneakiest possible way to be technically
honest, and it would be rubbish.

There's also a button called **Restore Purchases**. That's for "I already paid, but this is a new
phone and you've forgotten me." You tap it, the doorkeeper checks the guest list, and you're back
in. Nobody pays twice.

## Two small things we did that I'm quietly proud of

### 1. Saying "no thanks" is not an error

When the money screen appears and you decide *nah, not today*, and you tap Cancel — the app says
nothing. No red warning. No "PURCHASE FAILED". No little box you have to tap OK on.

Because nothing failed! You just changed your mind. Changing your mind is allowed.

It sounds tiny. It's actually the number one way apps make you feel told-off for not spending money,
and we went out of our way to make sure ours can't do it, even by accident.

### 2. If you paid, you stay paid — even when the internet breaks

Picture someone on a plane. No internet. They paid for Redact Pro last month. They open the app.

The app tries to check the guest list. There's nobody to ask. So what should it do?

The lazy answer: *"Can't check, so no entry."* Which means a person who **paid us actual money**
gets locked out of the thing they paid for, at 30,000 feet, because of something that isn't remotely
their fault.

We do the opposite. If we can't check, we **remember what we knew last time and let them in.** Yes,
this means someone whose subscription ran out five minutes ago might get a few extra minutes. Who
cares. That costs us almost nothing.

Locking out someone who paid costs us a person who will never trust us again. Not the same size of
mistake at all.

## Things that still aren't right

Same as always: here's the honest list, because pretending everything's perfect is how you end up
surprised.

**Three web pages don't exist yet.** There are two links on the money screen — one about privacy,
one about the rules — and right now they both go to "page not found". Apple *checks* those links
before a human even looks at the app, so if they're broken, we get sent to the back of the queue and
lose two days. A person has to go and make those pages. No amount of clever code can do it.

**Nobody's checked the app against Apple's full list of rules yet.** We *think* we've done
everything, but thinking and checking are different, and this project has already learned that
lesson painfully once.

**Nobody's pressed "Restore Purchases" on a real phone with a real purchase.** It's built. It looks
right. Nobody's proved it.

**There's a screen for managing your subscription that nobody can get to.** We built the room and
forgot the door. Slightly embarrassing, honestly, but better to write it down than pretend.

## The one thing to remember

If you remember nothing else from all of this:

> **You never buy a *thing* inside an app. You buy permission.**
>
> The app can't take your money — the shopping centre does, so that two million strangers don't all
> need your card details. The centre keeps a bit and sends the rest on.
>
> Someone has to remember you're allowed in. That's the doorkeeper with the list, and no money ever
> touches them.
>
> And if the doorkeeper can't be reached, the right answer is **let the person in**. They paid.
