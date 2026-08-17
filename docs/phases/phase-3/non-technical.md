---
id: phase-3-non-technical
date: 2026-08-17
phase: 3
audience: colleagues, management, non-engineers
tags: [phase-3, product, commercial, money, plain-language]
status: complete
---

# Phase 3 — The App Can Now Take Money

> For anyone who needs to explain this product, or its economics, without writing code.
> Siblings: [[phase-3-technical]] (for engineers) · [[phase-3-guide-for-kids]] (for a ten-year-old).
> Previous phase: [[phase-2-non-technical]].
> No prior knowledge assumed. Every technical word is defined the first time it appears.

## The headline

Phase 1 built an engine. Phase 2 built the car around it. Phase 3 fitted a till.

Redact now has a paid tier. There is a real subscription screen with real prices, a real "Restore
Purchases" button, the legal wording Apple requires, and — the part that actually matters — every
paid feature is now genuinely locked behind a check that asks a server whether this person has paid.
Not a placeholder. Not a constant set to `true`.

The build compiles, the tests pass, and the app launches and runs on the simulator with the paywall
in place. More than that: **somebody bought it.** In a test run on the simulator, the subscription
screen appeared with real plan prices, a test purchase went through, the screen dismissed itself,
and the app immediately switched to its paid behaviour. That is Milestone 3 — the first test
purchase — done and watched with human eyes, not inferred from a green build.

## How the money actually works

This is the part most people get wrong, including people who have shipped apps. It is worth reading
slowly, because it determines what we can promise, what we owe, and what we never have to build.

### Apple is the merchant of record

When someone buys Redact Pro, **they are not buying from us. They are buying from Apple.**

Apple takes the payment. Apple's name is on the customer's card statement and on the receipt. Apple
handles the refund if the customer asks for one. Apple collects and remits the sales tax, VAT or GST
in whichever of 175 countries the buyer happens to be sitting in. Apple deals with the chargeback if
somebody's card is stolen.

The term for this is **merchant of record** — the legal seller in the transaction. That is Apple, by
the rules of the App Store, for every digital good sold inside an iOS app. It is not optional and it
is not a choice we made.

What we get is a share of the proceeds, paid monthly, as a lump sum.

### Apple takes 15% or 30%

- **30%** is the standard rate.
- **15%** is the rate under the App Store Small Business Program, for developers earning under
  USD 1 million a year. We qualify comfortably, and will for the foreseeable future.
- **15%** is also the rate on any subscription after a subscriber has been paying for more than
  twelve consecutive months.

So the working number for us is **15%**. On a ₹399 monthly subscription, roughly ₹339 comes back to
us, before income tax. The exact figure moves with local tax rules, because Apple's cut is taken
after tax is stripped out.

### RevenueCat never touches the money

This surprises almost everyone, so it is worth being blunt: **RevenueCat is not a payment company.
No money passes through RevenueCat. Ever.**

RevenueCat is a bookkeeper and a switchboard. It does three things for us:

1. **Remembers who paid.** When Apple confirms a purchase, RevenueCat records that this person holds
   the thing we call the `pro` entitlement, and answers "is this person Pro?" for our app on every
   device they own, forever, including after they delete and reinstall.
2. **Lets us change the sales screen without shipping an update.** The subscription screen's layout,
   wording and imagery live in RevenueCat's dashboard, not in the app. We can rewrite it this
   afternoon and every user sees the new version — no App Review, no waiting 24–48 hours.
3. **Runs experiments and reports the numbers.** It can show half our users one version of the
   screen and half another, then tell us which one earned more.

RevenueCat charges us a percentage of tracked revenue above a free threshold. It is a software bill,
not a payment fee. If RevenueCat vanished overnight, the purchases would still be valid — they live
with Apple — we would simply lose the bookkeeping.

The plain-language version: **Apple is the shop. RevenueCat is the loyalty-card system that
remembers you already bought.**

### Payouts land in an Indian bank, in rupees

Apple pays out about 45 days after the close of each fiscal month, by bank transfer, into the Indian
bank account attached to our App Store Connect agreement, converted to **INR**.

The paperwork that makes this possible was finished on 2026-08-14 — Paid Apps Agreement active, bank
account active, W-8BEN active (the US tax form that stops Apple withholding 30% of our earnings at
source under the India–US tax treaty). That was the single item in this whole project capable of
costing us weeks. It cost a day.

Practical consequences worth knowing:

- Revenue arrives as **one payment per region group per month**, not per sale. Reconciliation is
  against Apple's reports, not against individual customers.
- We never see the customer's name, email or card. We could not, even if we wanted to.
- Foreign exchange is Apple's problem until the money hits the account, then ours.

### Why we never needed a payment gateway

We are an Indian developer. The obvious assumption is that selling a subscription means Razorpay or
Stripe, a merchant account, KYC, PCI compliance, recurring-mandate rules (India's e-mandate regime is
genuinely painful — cards need an explicit standing-instruction registration, and mandates above
₹15,000 need extra authentication), refund handling, dunning emails for failed payments, GST filing
on every transaction, and somebody responsible for storing card data safely.

**None of that exists in this project, and none of it ever will**, for one reason: Apple's rules
require digital goods inside an iOS app to be sold through Apple's own in-app purchase system.
A payment gateway inside the app would be an instant rejection.

What looks like a restriction is, for a solo developer, an enormous gift. Compare:

| If we ran our own payments | What we actually do |
|---|---|
| Merchant account, KYC, underwriting | Nothing |
| PCI compliance for card data | We never see a card |
| India e-mandate registration for recurring charges | Apple handles renewals |
| Tax registration and filing in every country we sell to | Apple remits the tax |
| Refund and chargeback handling | Apple's support team |
| Failed-payment retries and dunning emails | Apple's billing retry |
| Storing customer payment details securely | We store nothing |
| A backend server to hold accounts | We have no server and no accounts |

The 15% is the price of all of the above, and it is cheap. A standard Indian payment gateway charges
roughly 2% and gives you *only* the card processing — the tax, compliance, refunds, dunning and
support remain your problem, and you now need a server, a database of customers, and someone
accountable for it at 3am.

There is a second, subtler benefit that matters to this product specifically. Redact's core claim is
that it never sends your documents anywhere, has no accounts, and collects no data. That claim is
only truthful because we have no server. If we processed payments ourselves we would need customer
records, and the App Privacy label would have to say so.

**Not taking the money ourselves is part of the privacy story, not just a cost decision.**

## Free versus Pro

| | Free | Pro |
|---|---|---|
| Documents per month | 3 | Unlimited |
| Export format | PNG image, single page | PNG **and** multi-page PDF |
| Redaction quality | **Identical** | **Identical** |
| Works offline | Yes | Yes |
| Account required | No | No |
| Data sent anywhere | None | None |
| Multi-page / batch | — | Yes |
| Custom detection rules | — | Yes |
| Audit log — proof of what was removed | — | Yes |

Three plans are offered: monthly, yearly, and a one-time lifetime purchase. The yearly plan shows a
"Save X%" badge — and the X is calculated from the two real prices at the moment the screen is
drawn, so it can never claim a discount that no longer exists.

### Why the free tier stays genuinely useful

The temptation with a free tier is to cripple it just enough that people upgrade out of frustration.
We deliberately did the opposite, for three reasons.

**First, the promise has to be demonstrable.** Redact's whole argument is that the black boxes other
tools draw can be peeled off, and ours cannot. Nobody believes that from a marketing page. They
believe it after redacting their own payslip and seeing the result. If the free tier cannot do a
complete, real, genuinely-irreversible redaction, the product has no way of proving its one claim.

**Second, the limit is on volume, not on safety.** Free users get the same redaction engine, the
same destruction, the same metadata stripping. There is no "lite" mode where the black box is a
sticker. Shipping a paid tier that is *safer* than the free tier would be indefensible for a privacy
tool — a person redacting one document a year is often the person who most needs it right.

**Third, three documents a month is honestly enough for a casual user, and honestly not enough for a
professional one.** Somebody sending a redacted ID to a landlord twice a year should never pay us,
and should still get a correct result. A lawyer, an accountant, a recruiter or an HR team doing this
weekly hits the wall in the first week — and for them ₹399 a month is trivially worth it. That is
the line we want the wall to fall on, and volume draws it more honestly than crippling a feature
does.

The paywall reflects this. It never says "Upgrade to Pro". It names the wall the person actually
hit — *"You've used your three free documents"*, *"Export as PDF with Pro"* — and says what buying
removes. If someone is not ready, tapping Cancel does nothing at all: no error, no nag, no
interruption. They keep working.

## What was built this phase

**One place that knows whether you have paid.** The rest of the app asks it. Halfway through the
phase there were accidentally *two* such places, built in parallel by different agents — which is
exactly how a paying customer ends up looking paid to one screen and unpaid to another. It was found
in review and collapsed into one.

**A subscription screen with two ways of drawing itself.** The primary version is designed in
RevenueCat's dashboard, so its wording and layout can change without an app release. If it cannot be
fetched — bad connection, dashboard misconfiguration — the app draws its own version instead. A
blank screen where a purchase should be is a sale we lost, so there is always something real to buy.

**The legally required small print, compiled into the app.** Apple requires four things on a
subscription screen: a Restore Purchases button, a link to the terms, a link to the privacy policy,
and a plain sentence stating the price, the billing period, and that it renews automatically. All
four are drawn by our own code underneath *both* versions of the screen — so a mistake in the
dashboard can only ever add a duplicate, never remove the only copy.

**Prices that are never written down anywhere.** Every number on that screen is asked for from the
App Store at the moment it is displayed, in the user's own currency, for their own country. Writing
"₹399" into the app would be wrong for every buyer outside India and is itself a rejection cause.

**Every paid feature actually gated.** PDF export, the audit log, multi-page, custom rules, and the
monthly document limit all now check the entitlement.

## The rule we care most about: never lock out someone who paid

If the app cannot reach the internet, or the check fails, or a request times out, a paying user
**keeps everything they paid for**. The app trusts what it last knew and carries on.

The alternative — lock the door whenever we are unsure — is how a subscriber on a flight discovers
the thing they are paying for has stopped working. That is a refund, a one-star review, and a
customer we never get back. Very briefly honouring a subscription that has just expired costs us
almost nothing by comparison.

Redact itself works entirely offline. Only *buying* needs a connection, and the screen says so in
those words when it cannot reach the store.

## Honest status

**What is genuinely done:** the entitlement system, the paywall, the gating, and eleven automated
tests covering the cases that cost money or trust — cancellation is not an error, an expired
subscription revokes access, a network failure does not.

**What is not done, and is on someone's desk:**

1. **Three web pages do not exist yet.** The privacy policy, terms of use and support pages are
   linked from the paywall and are required by the App Store. They currently return "page not
   found". Apple checks the privacy policy URL automatically *before* a human reviewer ever opens
   the app — a broken link burns a full review cycle, at 24–48 hours a cycle, against a 5 September
   submission target. **This is the single highest-priority manual task in the project and no amount
   of code can fix it.** [[legal-urls-not-published]]
2. **Nobody has walked the App Review checklist.** The required elements are present by inspection,
   but the line-by-line pass against Apple's guidelines has not been done. That is scheduled for
   Phase 5.
3. **Nobody has tapped "Restore Purchases" on a real device with a real purchase.** It is built and
   reachable; it has not been exercised end to end.
4. **The self-service subscription management screen is built but not reachable.** Where it belongs
   in the app is a product decision that has not been made.

Nothing on that list is a surprise or a defect. They are the honest edge of the work.

## What this unlocks commercially

**Milestone 3 — the first test purchase — is done.** The app completed a purchase against
RevenueCat's Test Store, which needs no Apple product setup at all, and the app's behaviour changed
in response. Three of the five hackathon milestones are now complete.

**Phase 4 becomes a paperwork phase, not an engineering one.** Creating the App Store record and the
three purchase products, then swapping one line — the test key for the live key. The app's logic
does not change.

**The HAMM award case is now real.** That award rewards depth of RevenueCat usage rather than
audience size. We have remote paywalls, a server-side A/B experiment seam, contextual placements per
wall, and a Customer Center wrapper — not a single `purchase()` call.

## How to explain this phase in thirty seconds

> The app can now sell a subscription. Apple takes the money and sends us 85% of it in rupees, so we
> never needed a payment gateway, a server, or a single line of card-handling code — and that is
> also why our privacy claim stays true. RevenueCat remembers who paid and lets us redesign the
> sales screen without shipping an update. The free tier still does complete, genuinely irreversible
> redaction, three documents a month, because the product's only real argument is one you have to
> see for yourself. And if a paying user goes offline, they keep everything — we never lock out
> someone who paid.
