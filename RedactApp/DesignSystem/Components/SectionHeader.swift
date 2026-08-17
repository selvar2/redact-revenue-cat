import SwiftUI

/// The heading that opens a section: optional overline, title, optional subtitle,
/// optional trailing accessory.
///
/// It exists to make section rhythm identical everywhere. Hand-rolled headings
/// drift by two points of spacing and half a weight between screens — invisible
/// individually, obvious when a judge scrolls the whole app. It also solves a
/// VoiceOver problem once: the overline/title/subtitle trio must be read as a
/// *single* header element, not three unrelated labels, and must carry the
/// `.isHeader` trait so rotor navigation works.
public struct SectionHeader<Accessory: View>: View {

    private let overline: String?
    private let title: String
    private let subtitle: String?
    private let accessory: Accessory

    public init(
        _ title: String,
        overline: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.overline = overline
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Token.Space.sm) {
            VStack(alignment: .leading, spacing: Token.Space.xs) {
                if let overline {
                    Text(overline.uppercased())
                        .typeStyle(Typography.overline)
                        .foregroundStyle(Token.Accent.violetLight)
                }

                Text(title)
                    .typeStyle(Typography.headline)
                    .foregroundStyle(Token.Text.primary)

                if let subtitle {
                    Text(subtitle)
                        .typeStyle(Typography.callout)
                        .foregroundStyle(Token.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            accessory
        }
    }
}

public extension SectionHeader where Accessory == EmptyView {
    /// The common case: no trailing accessory.
    init(_ title: String, overline: String? = nil, subtitle: String? = nil) {
        self.init(title, overline: overline, subtitle: subtitle) { EmptyView() }
    }
}

#Preview("SectionHeader") {
    VStack(alignment: .leading, spacing: Token.Space.lg) {
        SectionHeader(
            "What we found",
            overline: "Step 2",
            subtitle: "Review each detection before anything is removed."
        )

        SectionHeader("Recent documents") {
            Pill("12", style: .accent, accessibilityLabel: "12 documents")
        }
    }
    .padding(Token.Space.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .ambientBackground()
    .preferredColorScheme(.dark)
}
