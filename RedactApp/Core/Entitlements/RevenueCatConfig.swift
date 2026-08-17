import Foundation
import RevenueCat

/// Every RevenueCat constant the app owns, in one file.
///
/// The SDK is the **only** permitted networking in this app (CLAUDE.md rule 1,
/// [[DEC-004-no-network]]). Nothing else here opens a connection, and no other file names an API
/// key, an entitlement, an offering or a product identifier — so "what does this build talk to,
/// and about what?" is answered by reading this one file.
public enum RevenueCatConfig {

    // MARK: - Key

    /// The **public SDK key** for the RevenueCat Test Store.
    ///
    /// Committing this is safe, and deliberately so. A public SDK key is shipped inside every copy
    /// of the binary; anyone can pull it out of an IPA with `strings` in a few seconds, which is
    /// why RevenueCat scopes it to operations that are harmless from an untrusted client — reading
    /// offerings, and posting receipts that the servers validate with Apple anyway. Treating it as
    /// a secret buys nothing and costs a keychain dance on every launch.
    ///
    /// **Secret keys are a categorically different thing.** `sk_…` REST keys, the App Store Connect
    /// `.p8`, the Key ID and the Issuer ID can mint entitlements and read customer data. None of
    /// them may ever appear in this repository, in this target, or in any Info.plist
    /// (CLAUDE.md rule 9). If you are about to paste a key that does not begin with `test_` or
    /// `appl_`, stop.
    ///
    /// **Phase 4 swaps the Test Store for the real App Store project by replacing this one line**
    /// with the `appl_…` public key from the RevenueCat dashboard. Nothing else in the app changes:
    /// the entitlement, offering and product identifiers below are already the production ones.
    public static let apiKey = "test_RWwnOzDVmDsnnYlBWDqFvzQkzwp"

    // MARK: - Identifiers

    /// The one entitlement that means "this user is Pro". Configured in the RevenueCat dashboard.
    public static let proEntitlementIdentifier = "pro"

    /// The offering the paywall shows. `current` is the dashboard-controlled default; asking for
    /// this identifier by name and *falling back* to `current` means a dashboard rename cannot
    /// leave the paywall with nothing to sell.
    public static let defaultOfferingIdentifier = "default"

    /// Store product identifiers, for reference and for the diagnostics screen.
    ///
    /// Deliberately **not** used to build a paywall: prices, currency, and billing period must come
    /// from `StoreProduct` at runtime because they differ per storefront and can be changed in App
    /// Store Connect without a new build. A hardcoded price is wrong abroad and is an App Review
    /// rejection.
    public enum ProductIdentifier {
        public static let monthly = "redact_pro_monthly"
        public static let annual = "redact_pro_annual"
        public static let lifetime = "redact_pro_lifetime"

        public static let all = [monthly, annual, lifetime]
    }

    /// Package identifiers within the offering. These are RevenueCat's standard package types.
    public enum PackageIdentifier {
        public static let monthly = "$rc_monthly"
        public static let annual = "$rc_annual"
        public static let lifetime = "$rc_lifetime"
    }

    // MARK: - Configuration

    /// Verbose enough in development to see why a purchase failed; quiet enough in release that the
    /// SDK is not writing a line per network call into the user's device log.
    public static var logLevel: LogLevel {
        #if DEBUG
        return .info
        #else
        return .error
        #endif
    }

    /// Configures the SDK. Called once, from `RedactApp.init()`.
    ///
    /// Idempotent by the `isConfigured` guard: SwiftUI previews and the test bundle both construct
    /// the app type more than once per process, and configuring twice logs a warning and rebuilds
    /// the caches for no reason.
    ///
    /// No `appUserID` is passed, so RevenueCat generates an anonymous one. That is the correct
    /// choice for this app rather than an oversight — Redact has no accounts, collects no
    /// identifiers, and answering "No Data Collected" truthfully means never sending it one.
    public static func configure() {
        guard !Purchases.isConfigured else { return }

        Purchases.logLevel = logLevel
        Purchases.configure(with: Configuration.builder(withAPIKey: apiKey).build())
    }
}
