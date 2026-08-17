import SwiftUI

/// The boxes drawn over detected personal information on the page.
///
/// Three things this view takes seriously:
///
/// 1. **Coordinates.** Every box comes from `RedactionRegion(detected:)` and is placed with
///    `displayRect(in:)`. There is no flip, no inset, and no arithmetic here — if the bar is in the
///    wrong place, the bug is in Core and one fix corrects the preview *and* the export together.
/// 2. **State without colour.** Colour groups the *category*. Whether a detection will be removed is
///    carried by three redundant cues: a solid versus dashed outline, a filled versus empty
///    interior, and a status glyph. Greyscale, colour-blind, and printed-out, the state still reads.
/// 3. **Reachability.** The drawn box tracks the text exactly, which for an 8pt card number is a few
///    points tall. The *touch* target is grown to the HIG minimum around the same centre, so the
///    smallest, most sensitive detections on the page are the ones that stay tappable.
@MainActor
struct DetectionOverlay: View {

    struct Item: Identifiable, Equatable {
        let detection: SessionDetection
        let region: RedactionRegion
        let isEnabled: Bool

        var id: SessionDetectionID { detection.id }

        /// Where the sweep has to reach before this box appears. Normalised down the page, which is
        /// what makes the reveal stagger in reading order without a single timer.
        var revealThreshold: CGFloat { region.rect.midY }
    }

    let items: [Item]
    let contentSize: CGSize
    let zoom: CGFloat
    let director: ScanlineDirector
    let onToggle: (SessionDetection) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                DetectionBox(
                    item: item,
                    rect: item.region.displayRect(in: contentSize),
                    zoom: zoom,
                    isRevealed: director.hasReached(item.revealThreshold),
                    hasLanded: director.hasLanded,
                    onToggle: { onToggle(item.detection) }
                )
            }
        }
        .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
    }
}

// MARK: - One box

@MainActor
private struct DetectionBox: View {

    let item: DetectionOverlay.Item
    let rect: CGRect
    let zoom: CGFloat
    let isRevealed: Bool
    let hasLanded: Bool
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { DetectionPalette.accent(for: item.detection.pii.kind) }

    var body: some View {
        let hit = EditorGeometry.hitSize(for: rect, zoom: zoom)

        Button(action: onToggle) {
            ZStack {
                // The expanded, invisible touch area. Sized independently of the artwork so the
                // outline never grows to match the finger.
                Color.clear
                    .frame(width: hit.width, height: hit.height)
                    .contentShape(Rectangle())

                shape
                    .frame(width: rect.width, height: rect.height)

                statusGlyph
                    .offset(x: -(rect.width / 2) - Token.Space.xs,
                            y: -(rect.height / 2) - Token.Space.xs)
            }
        }
        .buttonStyle(.plain)
        .opacity(isRevealed ? 1 : 0)
        .scaleEffect(isRevealed ? 1 : 0.86)
        .accessibleAnimation(Motion.snappy, value: isRevealed)
        .accessibleAnimation(Motion.standard, value: hasLanded)
        .accessibleAnimation(Motion.snappy, value: item.isEnabled)
        .position(x: rect.midX, y: rect.midY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(Text(String(
            localized: "Double tap to change whether this is removed.",
            comment: "VoiceOver hint on a detected item drawn over the page"
        )))
        .accessibilityAddTraits(item.isEnabled ? [.isButton, .isSelected] : .isButton)
    }

    /// Before the bars land, an enabled box is a tinted outline — the user is reviewing a *proposal*.
    /// After they land it fills in near-opaque, which is the app showing what the export will look
    /// like. Disabled is always an empty dashed outline, at every stage.
    @ViewBuilder
    private var shape: some View {
        let corner = RoundedRectangle(cornerRadius: EditorMetric.boxRadius, style: .continuous)

        if item.isEnabled {
            corner
                .fill(hasLanded
                      ? AnyShapeStyle(Color.black.opacity(EditorMetric.barPreviewOpacity))
                      : AnyShapeStyle(accent.opacity(EditorMetric.boxFillOpacity)))
                .overlay(
                    corner.strokeBorder(accent, lineWidth: EditorMetric.boxBorderStrong / zoom)
                )
        } else {
            corner
                .strokeBorder(
                    Token.Text.muted,
                    style: StrokeStyle(
                        lineWidth: EditorMetric.boxBorderWeak / zoom,
                        dash: EditorMetric.boxDash.map { $0 / zoom }
                    )
                )
        }
    }

    private var statusGlyph: some View {
        Image(systemName: DetectionPalette.statusSymbol(isEnabled: item.isEnabled))
            .font(.system(size: Token.Space.sm / zoom, weight: .bold))
            .foregroundStyle(item.isEnabled ? accent : Token.Text.muted)
            .accessibilityHidden(true)
    }

    private var accessibilityLabel: Text {
        Text("\(item.detection.pii.kind.displayName): \(item.detection.pii.text)")
    }

    private var accessibilityValue: Text {
        Text(item.isEnabled
             ? String(localized: "Will be removed", comment: "VoiceOver value: this detection is redacted on export")
             : String(localized: "Kept", comment: "VoiceOver value: this detection is left visible"))
    }
}

// MARK: - Metric note
//
// `font(.system(size:))` appears once above, for a decorative glyph whose size must track the box's
// zoom rather than Dynamic Type — a status marker pinned to a 6pt bar cannot grow to accessibility
// XXXL without covering the text it marks. The size is still a token (`Token.Space.sm`); the
// spoken label, which *is* the accessible path, carries the same information and is unaffected.
