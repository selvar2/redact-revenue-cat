# Gotcha: the legal URLs do not resolve yet — human task, blocks submission

**Status:** open. **Escalated to the human.** Nothing in the app target needs to change.

`RedactApp/App/LegalLinks.swift` points `privacyPolicy`, `termsOfUse` and `support` at

```
https://selvar2.github.io/redact-revenue-cat/privacy.html
https://selvar2.github.io/redact-revenue-cat/terms.html
https://selvar2.github.io/redact-revenue-cat/support.html
```

(Corrected 2026-08-17 by the phase-3 fixer: this file previously named the old
`senthilnathanraja.github.io/redact/...` host, which no longer matches the code. The host in the
code is authoritative; if the human publishes elsewhere, change `LegalLinks.swift` and this file
together.)

None of the three is published, and none could be verified from this machine. App Store Connect
validates the privacy policy URL as **metadata**, before a human reviewer ever opens the build, so a
404 burns a whole review cycle against the 2026-09-05 deadline. Both Terms of Use and Privacy Policy
are now live links on the paywall itself (observed in the simulator, `PaywallLegalFooter`), so a
reviewer tapping either and getting a 404 is its own rejection.

The fixer cannot resolve this: it requires publishing three pages under an account only the human
controls. The URLs in code are correct and must not be swapped for placeholders — a wrong URL that
resolves is worse than a right URL that does not yet.

**Action for the human, before the F13 milestone:** publish the three pages, then
`curl -sI <url>` each one and confirm `200` before submitting.
