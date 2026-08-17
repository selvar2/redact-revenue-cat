---
id: gotcha-xcode-select
date: 2026-08-17
phase: 0
tags: [gotcha, environment, blocked]
status: open
---

# Gotcha — iOS Simulator MCP blocked by xcode-select

## Symptom

`mcp__Claude_Code_iOS_Simulator__control { action: "attach" }` fails with:

> Xcode is installed but not selected. Run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

## Cause

The active developer directory points at the Command Line Tools rather than Xcode.app. `xcodebuild`
still works — the CLI resolves independently — which is why the build succeeds while the Simulator
integration does not.

## Fix — requires the human

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Needs a password. An agent cannot run this.

## Workaround in use

Driving the simulator through `simctl` directly:

```bash
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install "iPhone 17 Pro" <path>/RedactApp.app
xcrun simctl launch "iPhone 17 Pro" com.senthilnathanraja.redact
xcrun simctl io "iPhone 17 Pro" screenshot out.png
```

This is sufficient for verification — install, launch, and screenshot all work, and screenshots can
be read and judged directly.

## What is lost until it's fixed

The **live panel**: the user cannot watch the app run in real time, and tap/swipe/text injection is
unavailable, so interactive flows (scan → editor → export) have to be verified through scripted
launches and screenshots rather than by driving the UI.

Worth fixing before Phase 2, when the editor's interaction model needs real driving.

**Related:** [[2026-08-17-01]]
