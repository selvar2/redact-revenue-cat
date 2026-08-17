import CoreGraphics
import Foundation

/// Pure geometry for the editor canvas.
///
/// Everything here is a free function over values, with no view and no state, so it can be reasoned
/// about (and tested) without a running app.
///
/// **Coordinate space rule.** Every rect in this file is in *content points*: the coordinate space
/// of the displayed page image, origin top-left, y increasing downward, before zoom and pan are
/// applied. That is the same space `RedactionRegion.displayRect(in:)` returns and the same space
/// `RedactionRegion(userDrawnRect:in:)` expects. There is no Vision-space maths anywhere in the
/// Editor feature — the bottom-left→top-left flip happens once, inside Core, and a `1 - y` written
/// here would be the second flip that puts every bar on the wrong line.
enum EditorGeometry {

    /// The size an image of `pixelSize` occupies when aspect-fitted into `bounds`.
    ///
    /// The canvas needs this as a *value* rather than relying on `.aspectRatio` layout, because
    /// normalised regions can only be converted to points against a size we know exactly. Reading
    /// it back from a `GeometryReader` inside the fitted image would be a frame later than the
    /// gesture that needs it.
    static func fittedSize(for pixelSize: CGSize, in bounds: CGSize) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / pixelSize.width, bounds.height / pixelSize.height)
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }

    /// Clamps a pan offset so the zoomed page can never be dragged completely off screen.
    ///
    /// At zoom 1 the only legal offset is zero; beyond that the content may travel by half the
    /// overflow in each direction, which is what keeps a pinch-then-fling from losing the document.
    static func clampedPan(_ offset: CGSize, contentSize: CGSize, zoom: CGFloat) -> CGSize {
        let overflowX = max((contentSize.width * zoom) - contentSize.width, 0) / 2
        let overflowY = max((contentSize.height * zoom) - contentSize.height, 0) / 2
        return CGSize(
            width: min(max(offset.width, -overflowX), overflowX),
            height: min(max(offset.height, -overflowY), overflowY)
        )
    }

    /// The rect spanned by two gesture points, normalised so width and height are positive whatever
    /// direction the finger travelled.
    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x),
               y: min(start.y, end.y),
               width: abs(end.x - start.x),
               height: abs(end.y - start.y))
    }

    /// Constrains a rect to the page, so a drag that runs off the edge of the image cannot describe
    /// pixels that do not exist.
    static func confine(_ rect: CGRect, to contentSize: CGSize) -> CGRect {
        rect.standardized.intersection(CGRect(origin: .zero, size: contentSize))
    }

    /// Pulls each edge of a hand-drawn rect onto the nearest detected text edge within `threshold`.
    ///
    /// Hand-drawn boxes are the sloppiest input in the app: a finger dragged over an 8pt line lands
    /// two points high and clips an ascender, and a clipped ascender is a legible glyph. Snapping to
    /// the OCR geometry the page already knows about turns an approximate gesture into a box that
    /// covers a whole word — a correctness improvement, not a nicety.
    ///
    /// Each edge snaps independently, so a box drawn across two words still lands on the outer
    /// bounds of both rather than jumping wholesale onto one of them.
    static func snapped(
        _ rect: CGRect,
        to candidates: [CGRect],
        threshold: CGFloat = EditorMetric.snapDistance
    ) -> CGRect {
        guard !candidates.isEmpty else { return rect }

        // Only consider text the box actually touches; a distant line's edge is a coincidence,
        // not an intention.
        let nearby = candidates.filter { $0.intersects(rect.insetBy(dx: -threshold, dy: -threshold)) }
        guard !nearby.isEmpty else { return rect }

        let minXs = nearby.map(\.minX), maxXs = nearby.map(\.maxX)
        let minYs = nearby.map(\.minY), maxYs = nearby.map(\.maxY)

        let left = nearest(rect.minX, in: minXs, threshold: threshold) ?? rect.minX
        let right = nearest(rect.maxX, in: maxXs, threshold: threshold) ?? rect.maxX
        let top = nearest(rect.minY, in: minYs, threshold: threshold) ?? rect.minY
        let bottom = nearest(rect.maxY, in: maxYs, threshold: threshold) ?? rect.maxY

        let snapped = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        return snapped.width > 0 && snapped.height > 0 ? snapped : rect
    }

    private static func nearest(_ value: CGFloat, in options: [CGFloat], threshold: CGFloat) -> CGFloat? {
        options
            .filter { abs($0 - value) <= threshold }
            .min { abs($0 - value) < abs($1 - value) }
    }

    /// Expands a rect to at least ``Token/Size/minimumHitTarget`` on each side, about its own centre.
    ///
    /// A detected card number set in 8pt type is roughly a 6pt-tall box on screen. Tapping it is not
    /// a matter of care, it is impossible — so the *drawn* box stays true to the text while the
    /// *touchable* box is grown to the HIG minimum. Divided by `zoom` because the canvas is scaled:
    /// 44 content points at 2× is 88 screen points, which would swallow its neighbours.
    static func hitSize(for rect: CGRect, zoom: CGFloat) -> CGSize {
        let minimum = Token.Size.minimumHitTarget / max(zoom, EditorMetric.minimumZoom)
        return CGSize(width: max(rect.width, minimum), height: max(rect.height, minimum))
    }
}
