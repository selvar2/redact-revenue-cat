# instructions.md — Human Runbook

Everything **you** need to do by hand, in order. Agents handle the code; these steps need your Apple
ID, your credentials, or your judgment, and cannot be automated.

## Every session

```bash
./init.sh
```

Prints days remaining, environment, feature state, and where you left off. Start here always.

## One-time setup

### 1. Tooling

```bash
brew install asc
claude plugin marketplace add rorkai/app-store-connect-cli-skills
claude plugin install asc@rorkai
```

### 2. App Store Connect API key — **you must create this**

*appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API → generate key
(Admin or App Manager role).*

You receive a **Key ID**, an **Issuer ID**, and a `.p8` file that downloads **once and never again**.
Back it up somewhere safe outside the repo.

```bash
asc login   # stores in the macOS keychain, not in a file
```

> ⚠️ The `.p8` never enters the repo. It is full control of your developer account. `.gitignore`
> blocks `*.p8` from the first commit, but do not rely on that alone.

### 3. In-App Purchase key — separate key, for RevenueCat

*App Store Connect → Users and Access → Integrations → **In-App Purchase** → generate.*
This is a **different** key from the one above. Upload it to RevenueCat when you reach Phase 4.

### 4. RevenueCat

Create account → new project → add App Store app with bundle ID `com.senthilnathanraja.redact`.
Copy the **public SDK key** (safe to commit) and the **Test Store key** for Phase 3.
→ **Milestone 2 complete.**

## Already done — do not repeat

| Item | Status | Date |
|---|---|---|
| Shipaton registration (M1) | ✅ | — |
| Paid Apps Agreement | ✅ Active | 14 Aug 2026 |
| Bank account (INR payout) | ✅ Active | 14 Aug 2026 |
| W-8BEN, Article 12 @ 15% | ✅ Active | 14 Aug 2026 |
| Certificate of Foreign Status | ✅ Active | 14 Aug 2026 |

**Optional, low priority:** App Store Small Business Program (30% → 15% commission). Takes effect
the first of the month after approval, so it cannot help hackathon-period revenue. Five minutes,
whenever convenient.

## Daily loop

```bash
./init.sh          # where am I
./verify.sh        # does it still build and pass
python3 tools/memory_index.py query "how does detection handle PAN"
```

## Build and run

```bash
open RedactApp/RedactApp.xcodeproj          # or use the simulator MCP
xcodebuild -project RedactApp/RedactApp.xcodeproj -scheme RedactApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Shipping — TestFlight first, always

### Stage 1: TestFlight

```bash
asc signing setup
asc builds upload --app <APP_ID> --ipa <path>
asc testflight groups list
```

Then test **on a real device**, not the simulator:

- [ ] Redact a document, export it, and confirm the secret is unrecoverable in the exported file
- [ ] Purchase flow with a sandbox tester account
- [ ] VoiceOver navigates every screen
- [ ] Largest Dynamic Type — nothing clips
- [ ] `asc testflight feedback list` and `asc crash triage`

TestFlight builds get a lighter Apple review — you learn early if something offends the guidelines
without burning a full App Review cycle against the Sep 5 target.

### Stage 2: App Store — only after you personally sign off

```bash
asc metadata init --dir ./metadata
asc screenshots plan && asc screenshots apply
asc validate --app <APP_ID> --version 1.0     # must be zero blockers
asc publish appstore --app <APP_ID> --submit
asc status --app <APP_ID> --watch
```

**The gate between stages is yours, not an agent's.** Nothing is submitted until you have used the
TestFlight build yourself.

## Before you submit — the rejection list

Ordered by how often each one actually bounces first-time subscription apps:

1. **Restore Purchases** button visible on the paywall
2. **Terms of Use (EULA)** and **Privacy Policy** links on the paywall itself
3. Price, billing period, and auto-renewal stated in paywall text
4. Support URL and privacy policy URL both live and reachable
5. App Privacy questionnaire = **No Data Collected** (true for us — see [[DEC-004-no-network]])
6. Camera and photo purpose strings explain *why*, specifically
7. Sample document ships — reviewer gets value in 30 seconds with zero setup
8. No placeholders, no dead buttons, no "coming soon"

## If Apple rejects

Do not resubmit blind. Read the exact guideline number in Resolution Center, log it to
`docs/memory/gotchas/`, fix precisely that, and resubmit. Guessing costs another 24–48h per cycle,
and cycles are the only thing standing between you and the deadline.

## After going live

Buy your own subscription with your own Apple ID → **Milestone 5**. You get most of it back as a
payout, minus Apple's commission.
