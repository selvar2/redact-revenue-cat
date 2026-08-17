# Gotcha: the legal URLs do not resolve yet — human task, blocks submission

**Status:** open. **Escalated to the human.** Nothing in the app target needs to change.

`RedactApp/App/LegalLinks.swift` points `privacyPolicy`, `termsOfUse` and `support` at

```
https://senthilnathanraja.github.io/redact/privacy
https://senthilnathanraja.github.io/redact/terms
https://senthilnathanraja.github.io/redact/support
```

None of the three is published. App Store Connect validates the privacy policy URL as **metadata**,
before a human reviewer ever opens the build, so a 404 burns a whole review cycle against the
2026-09-05 deadline. The paywall also has to show working Terms and Privacy links (CLAUDE.md's App
Review checklist), and a link to a 404 from inside the app is its own rejection risk.

The fixer cannot resolve this: it requires publishing three GitHub Pages under an account only the
human controls. The URLs in code are correct and should not be changed to placeholders — a wrong
URL that resolves is worse than a right URL that does not yet.

**Action for the human, before the F13 milestone:** publish the three pages, then load each URL in a
browser and confirm a 200 before submitting.
