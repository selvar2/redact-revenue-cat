import RevenueCat
import SwiftUI

/// One selectable plan in the native paywall.
///
/// Selection state is carried by **shape and glyph as well as colour** — a filled checkmark and a
/// raised glass card, not a violet tint alone — so it survives greyscale and colour blindness
/// (`CLAUDE.md` rule 4), exactly as the editor's enabled/disabled detections do.
///
/// VoiceOver gets one element per plan whose label already contains the name, the price, the billing
/// period and the saving, because a blind user must be able to compare plans without hunting for a
/// separate price label.
struct PaywallPlanRow: View {

    let package: Package
    let isSelected: Bool
    let savingPercent: Int?
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Token.Space.sm) {
                selectionMark

                VStack(alignment: .leading, spacing: Token.Space.xs) {
                    HStack(spacing: Token.Space.xs) {
                        Text(planName)
                            .typeStyle(Typography.bodyEmphasis)
                            .foregroundStyle(Token.Text.primary)

                        if let savingPercent {
                            Pill(
                                String(
                                    format: String(localized: "Save %d%%", comment: "Badge: percentage saved on the annual plan"),
                                    savingPercent
                                ),
                                style: .accent
                            )
                        }
                    }

                    Text(PaywallPricing.priceLine(for: package))
                        .typeStyle(Typography.numeral)
                        .foregroundStyle(Token.Text.primary)

                    if let equivalent = PaywallPricing.equivalentMonthlyLine(for: package) {
                        Text(equivalent)
                            .typeStyle(Typography.caption)
                            .foregroundStyle(Token.Text.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: Token.Size.minimumHitTarget)
            // The glass card is applied *inside* the button's label, so the padded surface is part
            // of the tap target. Applied outside, the padding would look tappable and not be.
            .glassCard(elevation: isSelected ? .raised : .resting)
            .overlay(
                RoundedRectangle(cornerRadius: Token.Radius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(Token.gradient) : AnyShapeStyle(Token.Line.hairline),
                        lineWidth: Token.Size.hairlineWidth
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibleAnimation(Motion.snappy, value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(PaywallPricing.termsSentence(for: package))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(String(localized: "Selects this plan. Nothing is purchased until you confirm.", comment: "VoiceOver hint on a plan row"))
    }

    private var selectionMark: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(Typography.resolve(size: Typography.body.size, weight: .semibold, design: .rounded))
            .foregroundStyle(isSelected ? AnyShapeStyle(Token.gradient) : AnyShapeStyle(Token.Text.faint))
            .accessibilityHidden(true)
    }

    /// Falls back to the store's own product title rather than inventing a name, so a plan added in
    /// the dashboard is still described correctly without an app update.
    private var planName: String {
        switch package.packageType {
        case .annual:   return String(localized: "Yearly", comment: "Plan name: annual subscription")
        case .monthly:  return String(localized: "Monthly", comment: "Plan name: monthly subscription")
        case .lifetime: return String(localized: "Lifetime", comment: "Plan name: one-time purchase")
        default:        return package.storeProduct.localizedTitle
        }
    }

    private var accessibilityLabel: String {
        var parts = [planName, PaywallPricing.priceLine(for: package)]
        if let savingPercent {
            parts.append(
                String(
                    format: String(localized: "Saves %d percent compared with paying monthly", comment: "VoiceOver: annual saving"),
                    savingPercent
                )
            )
        }
        return parts.joined(separator: ", ")
    }
}
