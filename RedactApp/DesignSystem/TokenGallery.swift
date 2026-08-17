import SwiftUI

/// A single scrolling page rendering every token, surface, and component.
///
/// It exists because a design system has no tests worth writing: nothing in
/// `verify.sh` can tell you the amber is one stop too hot or that a card's
/// hairline vanished against the glow. The only honest verification is looking
/// at all of it at once, side by side, which is what this does. It also doubles
/// as the reference a feature agent scrolls before choosing a component.
///
/// Reached from a `#if DEBUG` button on `RootView` and from Xcode
/// previews. Both are compiled out of Release, so it adds no user-visible
/// surface (`CLAUDE.md` rule 10).
struct TokenGallery: View {

    @State private var meterFilled = false
    @State private var raisedCard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Token.Space.xl) {
                colours
                typography
                surfaces
                components
                motion
            }
            .padding(Token.Space.md)
            .padding(.vertical, Token.Space.lg)
        }
        .background(AmbientBackground(intensity: .subdued))
        .preferredColorScheme(.dark)
    }

    // MARK: - Colour

    private var colours: some View {
        VStack(alignment: .leading, spacing: Token.Space.md) {
            SectionHeader("Colour", overline: "Tokens", subtitle: "DEC-002 palette, dark-only for v1.")

            swatchRow("Background", [
                Swatch("base", Token.BG.base), Swatch("section", Token.BG.section),
                Swatch("card", Token.BG.card), Swatch("raised", Token.BG.raised)
            ])
            swatchRow("Accent", [
                Swatch("violet", Token.Accent.violet), Swatch("violetLight", Token.Accent.violetLight),
                Swatch("amber", Token.Accent.amber), Swatch("amberLight", Token.Accent.amberLight),
                Swatch("cyan", Token.Accent.cyan)
            ])
            swatchRow("Text", [
                Swatch("primary", Token.Text.primary), Swatch("muted", Token.Text.muted),
                Swatch("faint", Token.Text.faint)
            ])

            VStack(alignment: .leading, spacing: Token.Space.xs) {
                Text("Gradients").typeStyle(Typography.caption).foregroundStyle(Token.Text.faint)
                HStack(spacing: Token.Space.sm) {
                    gradientChip("gradient", Token.gradient)
                    gradientChip("gradientSoft", Token.gradientSoft)
                }
            }
        }
    }

    /// A named colour, so the swatch grid can be driven by `ForEach`.
    /// (`Identifiable` rather than a tuple: Swift has no key paths into tuples.)
    private struct Swatch: Identifiable {
        let id: String
        let color: Color
        init(_ id: String, _ color: Color) {
            self.id = id
            self.color = color
        }
    }

    private func swatchRow(_ name: String, _ entries: [Swatch]) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.xs) {
            Text(name).typeStyle(Typography.caption).foregroundStyle(Token.Text.faint)
            HStack(spacing: Token.Space.sm) {
                ForEach(entries) { entry in
                    VStack(spacing: Token.Space.xs) {
                        RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous)
                            .fill(entry.color)
                            .frame(width: 52, height: 52)
                            .overlay(
                                RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous)
                                    .strokeBorder(Token.Line.hairline,
                                                  lineWidth: Token.Size.hairlineWidth)
                            )
                        Text(entry.id)
                            .typeStyle(Typography.overline)
                            .foregroundStyle(Token.Text.muted)
                    }
                }
            }
        }
    }

    private func gradientChip(_ name: String, _ gradient: LinearGradient) -> some View {
        VStack(spacing: Token.Space.xs) {
            RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous)
                .fill(gradient)
                .frame(width: 120, height: 52)
            Text(name).typeStyle(Typography.overline).foregroundStyle(Token.Text.muted)
        }
    }

    // MARK: - Type

    private var typography: some View {
        VStack(alignment: .leading, spacing: Token.Space.md) {
            SectionHeader("Type", overline: "Tokens",
                          subtitle: "System stand-ins for Space Grotesk and Inter. Every style scales with Dynamic Type.")

            VStack(alignment: .leading, spacing: Token.Space.sm) {
                specimen("displayXL", Typography.displayXL)
                specimen("displayLarge", Typography.displayLarge)
                specimen("title", Typography.title)
                specimen("numeral", Typography.numeral)
                specimen("headline", Typography.headline)
                specimen("body", Typography.body)
                specimen("bodyEmphasis", Typography.bodyEmphasis)
                specimen("callout", Typography.callout)
                specimen("label", Typography.label)
                specimen("caption", Typography.caption)
                specimen("overline", Typography.overline)
            }
            .glassCard()
        }
    }

    private func specimen(_ name: String, _ style: Typography.Style) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).typeStyle(Typography.overline).foregroundStyle(Token.Text.faint)
            Text("Redact removes it permanently")
                .typeStyle(style)
                .foregroundStyle(Token.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Surfaces

    private var surfaces: some View {
        VStack(alignment: .leading, spacing: Token.Space.md) {
            SectionHeader("Surfaces", overline: "Glass",
                          subtitle: "Material over BG.card with a gradient hairline and the DEC-002 shadow.")

            VStack(alignment: .leading, spacing: Token.Space.xs) {
                Text("resting").typeStyle(Typography.overline).foregroundStyle(Token.Text.faint)
                Text("The default card. Deep, soft, low-opacity shadow.")
                    .typeStyle(Typography.body)
                    .foregroundStyle(Token.Text.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            VStack(alignment: .leading, spacing: Token.Space.xs) {
                Text("raised").typeStyle(Typography.overline).foregroundStyle(Token.Text.faint)
                Text("Lifts 6pt, border picks up the brand gradient, accent glow blooms.")
                    .typeStyle(Typography.body)
                    .foregroundStyle(Token.Text.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(elevation: raisedCard ? .raised : .resting)
            .onTapGesture { raisedCard.toggle() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Toggle raised elevation")

            VStack(alignment: .leading, spacing: Token.Space.xs) {
                Text("pressed").typeStyle(Typography.overline).foregroundStyle(Token.Text.faint)
                Text("Sinks toward the finger, shadow tightens.")
                    .typeStyle(Typography.body)
                    .foregroundStyle(Token.Text.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(elevation: .pressed)

            HStack(spacing: Token.Space.sm) {
                Text("glassCapsule")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(Token.Text.muted)
                    .padding(.horizontal, Token.Space.md)
                    .padding(.vertical, Token.Space.sm)
                    .glassCapsule()
            }
        }
    }

    // MARK: - Components

    private var components: some View {
        VStack(alignment: .leading, spacing: Token.Space.md) {
            SectionHeader("Components", overline: "Library",
                          subtitle: "Every control clears 44pt and carries a VoiceOver label.")

            PrimaryButton("Scan a document", systemImage: "doc.viewfinder") {}
            PrimaryButton("Redacting", isLoading: true) {}
            SecondaryButton("Choose from Photos", systemImage: "photo.on.rectangle") {}
            SecondaryButton("Restore Purchases", prominence: .plain) {}

            HStack(spacing: Token.Space.sm) {
                Pill("PDF")
                Pill("Pro", systemImage: "sparkles", style: .accent)
                Pill("Removed", systemImage: "checkmark", style: .success)
                Pill("PAN", style: .warning, accessibilityLabel: "PAN card number")
            }

            HStack(spacing: Token.Space.md) {
                IconWell("doc.viewfinder")
                IconWell("photo.on.rectangle", tint: .muted)
                IconWell("eye.slash.fill", size: 64, tint: .solid)
            }
        }
    }

    // MARK: - Motion

    private var motion: some View {
        VStack(alignment: .leading, spacing: Token.Space.md) {
            SectionHeader("Motion", overline: "Tokens",
                          subtitle: "Every curve here cross-fades instead when Reduce Motion is on.")

            VStack(alignment: .leading, spacing: Token.Space.sm) {
                Text("meter — 1.1s fill")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(Token.Text.faint)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Token.BG.raised)
                        Capsule()
                            .fill(Token.gradient)
                            .frame(width: meterFilled ? proxy.size.width : 0)
                    }
                }
                .frame(height: 10)
                .accessibleAnimation(Motion.meter, value: meterFilled)

                SecondaryButton(meterFilled ? "Reset meter" : "Fill meter") {
                    meterFilled.toggle()
                }
            }
            .glassCard()
        }
    }
}

#Preview("Token gallery") {
    TokenGallery()
}

#Preview("Token gallery — largest text") {
    TokenGallery()
        .environment(\.dynamicTypeSize, .accessibility5)
}

// A reduce-motion preview is deliberately absent: SwiftUI exposes
// `accessibilityReduceMotion` as read-only, so the setting cannot be forced from
// a preview. Verify it in the simulator under
// Settings → Accessibility → Motion → Reduce Motion.
