import Foundation
import RevenueCat

/// Every price, period and legal sentence the paywall shows, derived from `StoreProduct` at runtime.
///
/// Nothing here is a literal price. A hardcoded "₹399/month" is wrong in every storefront but one —
/// and Apple rejects a paywall whose stated price does not match what the App Store charges. The
/// only source of a number in this app is `StoreProduct`, which the SDK fills from StoreKit for the
/// user's own storefront, currency and locale.
///
/// Pure and `Sendable` so the wording can be reasoned about (and later tested) without a view.
enum PaywallPricing {

    // MARK: - Periods

    /// "month", "year", "3 months" — the noun that follows a slash in "₹399/month".
    ///
    /// Built from the calendar unit and the number of units rather than from a `DateComponentsFormatter`,
    /// because the formatter produces "1 month" and the price line needs the bare noun.
    static func periodName(_ period: SubscriptionPeriod) -> String {
        let singular: String
        let plural: String
        switch period.unit {
        case .day:
            singular = String(localized: "day", comment: "Billing period, singular")
            plural = String(localized: "days", comment: "Billing period, plural")
        case .week:
            singular = String(localized: "week", comment: "Billing period, singular")
            plural = String(localized: "weeks", comment: "Billing period, plural")
        case .month:
            singular = String(localized: "month", comment: "Billing period, singular")
            plural = String(localized: "months", comment: "Billing period, plural")
        case .year:
            singular = String(localized: "year", comment: "Billing period, singular")
            plural = String(localized: "years", comment: "Billing period, plural")
        @unknown default:
            // A period unit added by a future StoreKit. Falling back to the neutral word keeps the
            // sentence grammatical instead of printing an enum case at the user.
            singular = String(localized: "period", comment: "Billing period, singular, unknown unit")
            plural = String(localized: "periods", comment: "Billing period, plural, unknown unit")
        }
        guard period.value != 1 else { return singular }
        return String(
            format: String(localized: "%d %@", comment: "A count of billing periods, e.g. '3 months'"),
            period.value,
            plural
        )
    }

    // MARK: - The headline price line

    /// "₹399/month", or just the price for a one-time purchase.
    static func priceLine(for package: Package) -> String {
        let price = package.storeProduct.localizedPriceString
        guard let period = package.storeProduct.subscriptionPeriod else { return price }
        return String(
            format: String(localized: "%@/%@", comment: "Price per billing period, e.g. '₹399/month'"),
            price,
            periodName(period)
        )
    }

    /// "≈ ₹33/month" for an annual plan — the comparison a user actually makes.
    ///
    /// Divides the *real* annual price by the number of months it covers, so it is correct in every
    /// currency without a conversion table. Returns `nil` for anything that is not a multi-month
    /// subscription, where the line would be noise.
    static func equivalentMonthlyLine(for package: Package) -> String? {
        let product = package.storeProduct
        guard let period = product.subscriptionPeriod,
              let months = monthsCovered(by: period), months > 1,
              let formatter = product.priceFormatter else { return nil }
        let perMonth = product.price / Decimal(months)
        guard let formatted = formatter.string(from: perMonth as NSDecimalNumber) else { return nil }
        return String(
            format: String(localized: "≈ %@ per month", comment: "Annual plan broken down per month"),
            formatted
        )
    }

    // MARK: - Annual saving

    /// How much cheaper a year of `annual` is than twelve months of `monthly`, as a whole percent.
    ///
    /// Computed from the two real prices, never written down: the dashboard can change either
    /// product's price at any time, and a badge reading "Save 40%" over a plan that now saves 12%
    /// is a false claim on a purchase screen.
    ///
    /// Returns `nil` — and the badge is then not drawn at all — when the two products are priced in
    /// different currencies (nothing sensible to compare), when either period is missing, or when
    /// the annual plan is not actually cheaper.
    static func annualSavingPercent(annual: Package?, monthly: Package?) -> Int? {
        guard let annual, let monthly else { return nil }
        let annualProduct = annual.storeProduct
        let monthlyProduct = monthly.storeProduct
        guard annualProduct.currencyCode == monthlyProduct.currencyCode,
              let annualPeriod = annualProduct.subscriptionPeriod,
              let monthlyPeriod = monthlyProduct.subscriptionPeriod,
              let annualMonths = monthsCovered(by: annualPeriod),
              let monthlyMonths = monthsCovered(by: monthlyPeriod),
              monthlyMonths > 0, annualMonths > 0 else { return nil }

        let monthlyRate = monthlyProduct.price / Decimal(monthlyMonths)
        let annualRate = annualProduct.price / Decimal(annualMonths)
        guard monthlyRate > 0, annualRate < monthlyRate else { return nil }

        let saving = (monthlyRate - annualRate) / monthlyRate * 100
        let percent = Int((saving as NSDecimalNumber).doubleValue.rounded())
        return percent > 0 ? percent : nil
    }

    /// Whole months a period covers, or `nil` for day/week periods that do not divide evenly.
    private static func monthsCovered(by period: SubscriptionPeriod) -> Int? {
        switch period.unit {
        case .month: return period.value
        case .year:  return period.value * 12
        case .day, .week: return nil
        @unknown default: return nil
        }
    }

    // MARK: - The legally required sentence

    /// The auto-renewal disclosure Apple requires on the paywall, in plain language.
    ///
    /// Guideline 3.1.2 requires the price, the billing period and the fact of automatic renewal to
    /// be stated on the screen where the purchase happens — not in Settings, not behind a link. This
    /// is the one string in the app that must never be truncated, so every view that shows it uses
    /// `.fixedSize(horizontal: false, vertical: true)`.
    ///
    /// A non-renewing product (lifetime) gets the opposite sentence: claiming a one-time purchase
    /// renews is as wrong as omitting renewal from a subscription.
    static func termsSentence(for package: Package) -> String {
        let product = package.storeProduct
        guard let period = product.subscriptionPeriod else {
            return String(
                format: String(
                    localized: "%@ once. This is a one-time purchase, not a subscription: nothing renews and there is nothing to cancel.",
                    comment: "Auto-renewal disclosure for a non-renewing lifetime purchase"
                ),
                product.localizedPriceString
            )
        }

        let base = String(
            format: String(
                localized: "%@ per %@. Renews automatically until cancelled. Cancel any time in Settings, at least 24 hours before the period ends.",
                comment: "Required auto-renewal disclosure: price, billing period, renewal, how to cancel"
            ),
            product.localizedPriceString,
            periodName(period)
        )

        guard let intro = product.introductoryDiscount else { return base }
        let introPeriod = periodName(intro.subscriptionPeriod)
        let opener: String
        switch intro.paymentMode {
        case .freeTrial:
            opener = String(
                format: String(
                    localized: "Free for %@, then ",
                    comment: "Introductory free trial prefix to the renewal disclosure"
                ),
                introPeriod
            )
        case .payUpFront, .payAsYouGo:
            opener = String(
                format: String(
                    localized: "%@ for the first %@, then ",
                    comment: "Introductory price prefix to the renewal disclosure"
                ),
                intro.localizedPriceString,
                introPeriod
            )
        @unknown default:
            return base
        }
        return opener + base
    }
}
