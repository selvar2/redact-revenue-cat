---
id: phase-5-technical
date: 2026-08-18
phase: 5
tags: [phase-doc, technical, testflight, signing, build]
status: in-progress
audience: engineers
---

# Phase 5 — Technical

> Getting a signed build onto TestFlight. Build 2 is **VALID**.
> Plain language: [[phase-5-non-technical]] · For a 10-year-old: [[phase-5-guide-for-kids]]

## Outcome

```
asc status --app 6802355309
  health: yellow  ← was red
  builds.latest: { buildNumber: "2", version: "1.0", processingState: "VALID" }
  nextAction: "Prepare metadata and submit for review."
```

`VALID` is Apple confirming the binary passed processing. Getting there took **four** distinct
failures, and two of my diagnoses were wrong before the right one. The wrong turns are the useful
part of this document.

## The pipeline that works

```bash
# 1. Authenticate. asc reads env vars; it refuses a world-readable key (correctly).
chmod 600 ~/Downloads/AuthKey_XXXXXXXXXX.p8
export ASC_KEY_ID=…  ASC_ISSUER_ID=…  ASC_PRIVATE_KEY_PATH=~/Downloads/AuthKey_…p8

# 2. Archive. DEVELOPMENT_TEAM must be set in project.yml or signing has nothing to resolve.
PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" \
xcodebuild -project RedactApp.xcodeproj -scheme RedactApp \
  -destination 'generic/platform=iOS' -archivePath build/Redact.xcarchive \
  -allowProvisioningUpdates archive

# 3. Export. The PATH prefix is load-bearing — see failure 3.
PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" \
xcodebuild -exportArchive -archivePath build/Redact.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates

# 4. Upload
asc builds upload --app 6802355309 --ipa build/export/RedactApp.ipa
```

`ExportOptions.plist` — `method: app-store-connect`, `teamID`, `signingStyle: automatic`,
`uploadSymbols: true`.

## Failure 1 — codesign hangs on a keychain prompt

**Symptom:** the export never returns. No output, no error.

**Diagnosis:** a hung export is indistinguishable from a slow one until you look for the cause:

```bash
$ ps aux | grep -E "SecurityAgent|codesign"
… SecurityAgent.bundle/Contents/MacOS/SecurityAgent   ← a GUI prompt is on screen
```

`SecurityAgent` running means macOS is waiting on a human. No amount of waiting helps.

## Failure 2 — the signing key was in a foreign keychain

The prompt wanted the **`dbx-build`** keychain (Dropbox build tooling), not login — and its password
was long forgotten. The certificate's private key lived there:

```bash
$ for kc in $(security list-keychains | tr -d ' "'); do
    echo "$kc → $(security find-identity -v -p codesigning "$kc" | grep -c 'iPhone Distribution')"
  done
dbx-build.keychain-db → 1     ← the key we needed
login.keychain-db     → 0
```

**Resolved without the password** by narrowing the search list:

```bash
security list-keychains -s ~/Library/Keychains/login.keychain-db /Library/Keychains/System.keychain
```

Non-destructive — `dbx-build` stays on disk and is restored by re-adding it to the list. With no
usable distribution identity visible, `-allowProvisioningUpdates` made Xcode mint a **second**
certificate (`Apple Distribution`, the modern unified type) into the login keychain, plus a store
provisioning profile.

Apple allows **2 active distribution certificates**. This *added* one rather than revoking, so
nothing depending on the old certificate broke. Revoking is possible and unlimited, but it
invalidates every provisioning profile built on that cert and breaks anything still signing with it.
Apps already live on the App Store are unaffected by a revocation.

Note: modifying the keychain search list was **blocked by the permission classifier** as a system
security setting, and escalated to the human rather than worked around. That was the correct
boundary.

## Failure 3 — a third-party `rsync` on PATH

**Symptom:** `error: exportArchive Copy failed`. That is the entire message, and it points nowhere
near the truth.

**Real cause**, only visible in the distribution log bundle:

```
Running /usr/bin/rsync '-8aPhhE' … 
rsync: on remote machine: --extended-attributes: unknown option   [server=3.4.1]
Step "IDEDistributionCreateIPAStep" failed with error "Copy failed"
```

Xcode calls Apple's `/usr/bin/rsync` by absolute path, but rsync resolves its own **server-side
child from `PATH`**. Here `/opt/local/bin/rsync` (MacPorts 3.4.1) won, and 3.4.1 spells that flag
`--xattrs` and rejects `--extended-attributes`. Two different rsyncs in one operation.

The giveaway is `[server=3.4.1]` while the client is Apple's openrsync.

**Fix:** prefix system paths for that invocation only. No system change, no uninstall.

Full write-up: [[gotcha-rsync-shadowing-breaks-export]].

## Failure 4 — no app icon, rejected silently

**Symptom:** upload succeeds and returns an uploadId; `asc builds list` returns **0 builds**,
indefinitely. No error anywhere in the tooling.

**Cause:** `AppIcon.appiconset` contained only a `Contents.json` declaring a 1024×1024 slot with no
`filename` and no PNG. App Store Connect rejects such a binary during processing and notifies only
by email.

`asc status` frames it but does not explain it:

```
health: red · nextAction: "Resolve blocker: No builds found for this app"
```

**Fix:** `tools/make_app_icon.swift` renders the icon with CoreGraphics from the same DEC-002 tokens
the app uses — the 135° violet `#A855F7` → amber `#FF6B3D` gradient and the eye-slash mark from
`RootView`. Generated rather than hand-drawn so it cannot drift from the app's identity, and it
reproduces anywhere Swift runs.

Three ways an icon fails silently; the generator avoids all three:

| Trap | Guard |
|---|---|
| Missing file | `verify.sh` fails if no PNG in the iconset |
| Alpha channel | Context uses `CGImageAlphaInfo.noneSkipLast`; `sips` confirms `hasAlpha: no` |
| Wrong dimensions | Exactly 1024×1024, asserted in `verify.sh` |

**Proof it shipped**, rather than assumption: the IPA grew **11,568,981 → 12,021,381 bytes**, and the
archive's `Info.plist` gained `CFBundleIconName = AppIcon`. A ~450 KB delta is a cheap, checkable
fact.

Build number bumped **1 → 2**: Apple reserves build numbers even for rejected uploads.

## Harness gap this exposed

`verify.sh` enforced rule 10 (no placeholders) against **strings in source**. It never checked that
required **binary assets** exist. A build can be perfectly valid Swift and still be un-shippable.

Added step 4b: fails the gate on a missing, mis-sized, or transparent icon.

> **A checklist that only inspects code misses everything the build needs but the code never
> mentions.**

## Diagnostic lessons worth keeping

1. **`xcodebuild`'s summary line lies.** "Copy failed" meant a PATH collision. Always open the
   `*.xcdistributionlogs` bundle whose path is printed in the output.
2. **A silent success is not a success.** The upload returned `uploaded: true` for a binary Apple
   would reject. Verify at the *destination* (`asc status`), not at the point of sending.
3. **Check for GUI prompts before assuming a hang.** `ps aux | grep SecurityAgent`.
4. **Size deltas are evidence.** 450 KB is not proof of correctness, but it is proof the asset is
   present — far better than trusting that a build step "should have" included it.

## Remaining in Phase 5

| Item | Blocks |
|---|---|
| TestFlight group + testers (`testflight: {}` is empty) | installing on a real device |
| Localization on both IAP products | submission |
| App Store metadata: description, keywords, screenshots, privacy + support URLs | submission |
| Rotate `AuthKey_CDCMHRBW3C` → App Manager scope | good hygiene; also unblocks RevenueCat import |

**Related:** [[phase-4-technical]] · [[gotcha-rsync-shadowing-breaks-export]]
