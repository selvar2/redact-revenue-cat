import Foundation

/// Every externally-hosted URL the app can open, in one place.
///
/// App Review requires a Privacy Policy and a Terms of Use (EULA) link **on the paywall itself**,
/// not only in Settings, and rejects when either 404s. Both requirements are one-line changes here
/// rather than a search through the feature tree.
///
/// These are the *only* URLs in the app, and nothing fetches them: they are handed to
/// `SFSafariViewController`/`openURL`, which loads them in Safari, outside our process. That is not
/// a network call by this app and does not affect the "No Data Collected" declaration
/// (CLAUDE.md rule 1, DEC-004). No code in this target may hand these to a networking API.
public enum LegalLinks {

    /// Published as GitHub Pages alongside the repository.
    ///
    /// **These pages must be live before submission.** A reachable, correct privacy policy URL is
    /// checked by App Review and by App Store Connect's metadata validation.
    public static let privacyPolicy = url("https://senthilnathanraja.github.io/redact/privacy")

    /// Terms of Use (EULA). Apple's standard EULA is acceptable, but linking our own keeps the
    /// paywall's two required links symmetrical and under our control.
    public static let termsOfUse = url("https://senthilnathanraja.github.io/redact/terms")

    /// Support contact, required by App Store Connect metadata and worth surfacing in-app so a
    /// confused user has somewhere to go that is not a one-star review.
    public static let support = url("https://senthilnathanraja.github.io/redact/support")

    /// Force-unwraps a compile-time-constant literal. These strings never come from user input or
    /// from disk, so a failure here is a typo caught on the first launch of the first build, not a
    /// runtime condition anything can recover from.
    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("LegalLinks contains a malformed URL literal: \(string)")
        }
        return url
    }
}
