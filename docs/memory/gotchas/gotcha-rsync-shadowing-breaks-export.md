---
id: gotcha-rsync-shadowing-breaks-export
date: 2026-08-18
phase: 5
tags: [gotcha, build, signing, testflight, resolved]
status: resolved
---

# Gotcha — a third-party `rsync` on PATH breaks `xcodebuild -exportArchive`

## Symptom

```
error: exportArchive Copy failed
** EXPORT FAILED **
```

That is the entire user-facing message. It says nothing true about the cause, and it strongly
suggests a disk or permissions problem. It is neither.

## Real cause, from the distribution log

```
Running /usr/bin/rsync '-8aPhhE' … '--link-dest' … 
rsync: on remote machine: --extended-attributes: unknown option
rsync error: syntax or usage error (code 1) at main.c(1802) [server=3.4.1]
rsync(60451): error: unexpected end of file
Step "IDEDistributionCreateIPAStep" failed with error "Copy failed"
```

Xcode invokes **`/usr/bin/rsync`** by absolute path — Apple's `openrsync`, which accepts `-E`
(`--extended-attributes`). But rsync forks a *server* side for the copy, and that child is resolved
from **`PATH`**, not by absolute path. On this machine:

```bash
$ which -a rsync
/opt/local/bin/rsync      # MacPorts, rsync 3.4.1  ← wins
/usr/bin/rsync            # Apple openrsync, protocol 29
```

rsync 3.4.1 spells the same feature `--xattrs` and rejects `--extended-attributes`. Apple's client
and a GNU-lineage server therefore cannot talk to each other, and the IPA packaging step dies.

Note the giveaway in the log: **`[server=3.4.1]`** while the client is Apple's. Two different rsyncs
in one operation is the whole bug.

## Fix

Put the system paths first for the export only. No system change, no PATH edit, no uninstall:

```bash
PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" xcodebuild -exportArchive \
  -archivePath build/Redact.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates
```

Result: `** EXPORT SUCCEEDED **`, `RedactApp.ipa` (11 MB).

Anything that shells out to `rsync` during an Xcode distribution — and `asc builds upload` may too —
should carry the same PATH prefix. It is cheap insurance.

## Why this cost time

Two wrong diagnoses came first, and both were plausible:

1. **"It's the keychain."** The previous run *had* genuinely hung on a `SecurityAgent` prompt, so
   when the next one failed it looked like the same problem continuing. It was not — signing had
   completed successfully by then. The log proves it: Xcode found
   `Apple Distribution: SENTHILNATHAN RAJA (8837BPRM4M)` and generated a store provisioning profile
   before the failing step ran.
2. **"It's stale state from my `pkill`."** I had killed the hung export, which can leave temp
   artifacts. Plausible, and wrong — the retry failed identically, which is what ruled it out.

What actually solved it was reading `IDEDistributionPipeline.log` inside the
`*.xcdistributionlogs` bundle instead of trusting `xcodebuild`'s summary line.

**Rule: when Xcode says "Copy failed", go straight to the distribution log bundle.** The path is
printed in the output:

```
IDEDistribution: Created bundle at path "/var/folders/…/RedactApp_<timestamp>.xcdistributionlogs"
```

**Related:** [[phase-5-technical]] · [[gotcha-asc-form-automation]]
