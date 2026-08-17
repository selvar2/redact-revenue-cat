import SwiftUI

/// Hand-drawn redaction boxes: the escape hatch for everything detection did not find.
///
/// A signature, a face, a handwritten note, a logo — none of those are text and none of them will
/// ever appear in the detection list, so without this layer the app can only redact what it happens
/// to recognise. That is a much weaker product promise than "remove personal information from this
/// document", so manual boxes are a first-class path, not a fallback.
///
/// Every gesture here has a non-gesture equivalent (see ``DetectionListSheet`` for the list, and the
/// per-box VoiceOver actions below for resize and delete), because dragging a corner handle on a
/// zoomed canvas is exactly the interaction a screen-reader user cannot perform.
@MainActor
struct ManualRegionLayer: View {

    let regions: [ManualRegion]
    let contentSize: CGSize
    let zoom: CGFloat
    @Binding var selectedID: UUID?
    /// Called when a resize gesture or an adjustable action finishes.
    let onResize: (ManualRegion, CGRect) -> Void
    let onDelete: (UUID) -> Void

    @State private var resize: ResizeDrag?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(regions) { manual in
                let base = manual.region.displayRect(in: contentSize)
                let rect = resize?.id == manual.id ? resize?.rect ?? base : base

                ManualBox(
                    rect: rect,
                    zoom: zoom,
                    isSelected: selectedID == manual.id,
                    label: label(for: manual),
                    onSelect: { selectedID = selectedID == manual.id ? nil : manual.id },
                    onDelete: { onDelete(manual.id) },
                    onAdjust: { direction in
                        onResize(manual, adjusted(rect, by: direction))
                    }
                )
                .overlay {
                    if selectedID == manual.id {
                        ResizeHandles(
                            rect: rect,
                            zoom: zoom,
                            onChange: { corner, translation in
                                resize = ResizeDrag(
                                    id: manual.id,
                                    rect: EditorGeometry.confine(
                                        corner.applying(translation, to: base),
                                        to: contentSize
                                    )
                                )
                            },
                            onEnd: {
                                if let rect = resize?.rect { onResize(manual, rect) }
                                resize = nil
                            }
                        )
                    }
                }
            }
        }
        .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
    }

    private func label(for manual: ManualRegion) -> String {
        String(
            localized: "Hand-drawn redaction box",
            comment: "VoiceOver label for a redaction rectangle the user drew"
        )
    }

    /// Grows or shrinks about the centre. This is what a VoiceOver adjustable action maps onto —
    /// one axis of control is not enough to place a box, but combined with the list's delete and the
    /// "cover this detection" path it is enough to correct one.
    private func adjusted(_ rect: CGRect, by direction: AdjustDirection) -> CGRect {
        let delta = direction == .increment ? -Token.Space.sm : Token.Space.sm
        let grown = rect.insetBy(dx: delta, dy: delta)
        guard grown.width > EditorMetric.minimumDraftSide,
              grown.height > EditorMetric.minimumDraftSide else { return rect }
        return EditorGeometry.confine(grown, to: contentSize)
    }
}

enum AdjustDirection { case increment, decrement }

private struct ResizeDrag {
    let id: UUID
    let rect: CGRect
}

// MARK: - One manual box

@MainActor
private struct ManualBox: View {

    let rect: CGRect
    let zoom: CGFloat
    let isSelected: Bool
    let label: String
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onAdjust: (AdjustDirection) -> Void

    var body: some View {
        let corner = RoundedRectangle(cornerRadius: EditorMetric.boxRadius, style: .continuous)

        Button(action: onSelect) {
            ZStack {
                corner
                    .fill(Color.black.opacity(EditorMetric.barPreviewOpacity))
                corner
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(Token.gradient) : AnyShapeStyle(Token.Accent.violetLight),
                        lineWidth: (isSelected ? EditorMetric.boxBorderStrong : EditorMetric.boxBorderWeak) / zoom
                    )
            }
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: rect.midX, y: rect.midY)
        .accessibleAnimation(Motion.snappy, value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(String(
            localized: "Will be removed",
            comment: "VoiceOver value: a hand-drawn box is always redacted"
        )))
        .accessibilityHint(Text(String(
            localized: "Swipe up or down to resize. Use the delete action to remove it.",
            comment: "VoiceOver hint for a hand-drawn redaction box"
        )))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onAdjust(.increment)
            case .decrement: onAdjust(.decrement)
            @unknown default: break
            }
        }
        .accessibilityAction(named: Text(String(
            localized: "Delete box",
            comment: "VoiceOver action that removes a hand-drawn redaction box"
        ))) {
            onDelete()
        }
    }
}

// MARK: - Handles

/// The four corner handles shown on the selected box.
///
/// Each dot is drawn at ``EditorMetric/handleDot`` but padded out to the 44pt minimum, so the
/// touchable area is comfortable even when the visible dot is deliberately small enough not to
/// obscure the document underneath.
@MainActor
private struct ResizeHandles: View {

    enum Corner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        func point(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeading:     CGPoint(x: rect.minX, y: rect.minY)
            case .topTrailing:    CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomLeading:  CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomTrailing: CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }

        /// Applies a drag translation to the corner this handle owns, leaving the opposite corner
        /// anchored — which is what makes a resize feel like pulling an edge rather than moving the
        /// whole box.
        func applying(_ translation: CGSize, to rect: CGRect) -> CGRect {
            var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
            switch self {
            case .topLeading:     minX += translation.width; minY += translation.height
            case .topTrailing:    maxX += translation.width; minY += translation.height
            case .bottomLeading:  minX += translation.width; maxY += translation.height
            case .bottomTrailing: maxX += translation.width; maxY += translation.height
            }
            return CGRect(x: min(minX, maxX), y: min(minY, maxY),
                          width: abs(maxX - minX), height: abs(maxY - minY))
        }

        var accessibilityName: String {
            switch self {
            case .topLeading:     String(localized: "Top left handle", comment: "Resize handle")
            case .topTrailing:    String(localized: "Top right handle", comment: "Resize handle")
            case .bottomLeading:  String(localized: "Bottom left handle", comment: "Resize handle")
            case .bottomTrailing: String(localized: "Bottom right handle", comment: "Resize handle")
            }
        }
    }

    let rect: CGRect
    let zoom: CGFloat
    let onChange: (Corner, CGSize) -> Void
    let onEnd: () -> Void

    var body: some View {
        ForEach(Corner.allCases, id: \.self) { corner in
            let dot = EditorMetric.handleDot / zoom
            let target = Token.Size.minimumHitTarget / zoom

            Circle()
                .fill(Token.gradient)
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: Token.Size.hairlineWidth / zoom))
                .frame(width: dot, height: dot)
                .frame(width: target, height: target)
                .contentShape(Rectangle())
                .position(corner.point(in: rect))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { onChange(corner, $0.translation) }
                        .onEnded { _ in onEnd() }
                )
                // Handles are a pointer affordance. VoiceOver resizes through the box's own
                // adjustable action instead, so exposing four unlabelled dots would only add noise.
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Draft

/// The box being drawn right now, before the finger lifts.
///
/// Rendered in the brand gradient rather than as a black bar, because until it is committed it is a
/// selection, not a redaction — and showing it as an opaque bar would imply the content underneath
/// is already gone.
@MainActor
struct DraftRegionView: View {

    let rect: CGRect
    let zoom: CGFloat
    let isSnapped: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: EditorMetric.boxRadius, style: .continuous)
            .fill(Token.gradientSoft)
            .overlay(
                RoundedRectangle(cornerRadius: EditorMetric.boxRadius, style: .continuous)
                    .strokeBorder(
                        Token.gradient,
                        style: StrokeStyle(
                            lineWidth: EditorMetric.boxBorderStrong / zoom,
                            dash: isSnapped ? [] : EditorMetric.boxDash.map { $0 / zoom }
                        )
                    )
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
