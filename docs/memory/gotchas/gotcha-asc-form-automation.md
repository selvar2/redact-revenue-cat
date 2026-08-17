---
id: gotcha-asc-form-automation
date: 2026-08-17
phase: 4
tags: [gotcha, automation, appstore, browser]
status: resolved
---

# Gotcha — App Store Connect forms resist browser automation

Two distinct failures, both hit while creating the app record. Read this before automating ASC again.

## 1. Native `<select>` popups render outside the page

**Symptom:** set the value, the field visually reverts to "Choose" and shows *"This field is
required"*. Keyboard type-ahead does nothing. Clicking the select appears to do nothing.

**Cause:** two problems stacked.
- The dropdown list is drawn by the OS, not the DOM, so synthetic clicks and key events never reach it.
- Setting `.value` directly bypasses React's synthetic event system, so component state never updates
  even though the DOM property changed.

**Fix — native prototype setter plus real events:**

```js
const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value').set;
setter.call(el, 'com.senthilnathanraja.redact');
el.dispatchEvent(new Event('input',  { bubbles: true }));
el.dispatchEvent(new Event('change', { bubbles: true }));
```

The prototype setter is what React's value tracker watches; without it React sees no change and
discards the update on the next render.

## 2. Coordinate clicks are unreliable on this site

**Symptom:** a button clicked at coordinates read from a screenshot does nothing, or hits the wrong
element. Menus open and immediately close.

**Cause:** App Store Connect re-renders at different zoom/viewport scales between screenshots
(observed 1568×753 → 1168×505 → 1752×841 within one session). A coordinate captured in one frame
points somewhere else in the next.

**Fix:** click by **element reference** (`find` → `ref_N` → click by ref). This worked every single
time coordinates failed, including for menu items inside dropdowns that had defeated three
coordinate attempts.

## 3. Order of operations: register the App ID first

The **New App** dialog silently fails to open when the account has no unregistered bundle IDs
available. No error, no message — the menu simply closes. Register the App ID at
*developer.apple.com → Identifiers* first, and the dialog opens immediately.

## Rule

> On App Store Connect: refs over coordinates, prototype setter + real events over `.value`, and
> register identifiers before creating records.

**Related:** [[phase-4-technical]]
