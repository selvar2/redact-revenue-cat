import CoreGraphics
import Foundation

// MARK: - Why this file contains no `RedactionRegion` declaration
//
// `RedactionRegion`, `PageRedaction`, `RedactionStyle` and `RedactionBarInk` are already declared
// by `Core/Redaction/RedactionStyle.swift`. Everything in this app target compiles into one module,
// so a second declaration of the same name is a redeclaration error, not a shadow — Phase 1 lost
// time to exactly that with two `Models.swift` files. The feature layer therefore *extends* the
// Core type and never restates it.
//
// The one rule every feature agent must respect: `RedactionRegion.rect` is normalised 0...1 with a
// **top-left** origin. `TextSpan.boundingBox` is normalised 0...1 with a **bottom-left** origin.
// The flip lives in exactly two places — `RedactionRegion.init(visionBoundingBox:style:)` and
// `TextSpan.topLeftOriginBoundingBox` — and nowhere else. Do not write `1 - y` in a view.

extension RedactionRegion {

    /// Builds the region that destroys a detection, in the coordinate space the export path wants.
    ///
    /// This is the only supported way to turn a `DetectedPII` into something drawable or burnable.
    /// It does two things a call site would otherwise have to remember:
    ///
    /// 1. Flips Vision's bottom-left origin to top-left, via Core's single conversion initialiser.
    /// 2. Grows the box by `padding` on every side. OCR boxes hug the glyphs, and a bar that hugs
    ///    the glyphs leaves ascenders, descenders and the leading edge of the first character
    ///    poking out. A sliver of a digit narrows a guess, so the margin is a correctness measure,
    ///    not a cosmetic one. It is clamped to the unit square so a padded region can never
    ///    describe pixels outside the page.
    ///
    /// Returns `nil` when the detection has no OCR geometry (`TextSpan.hasGeometry == false`) —
    /// pasted-text detections can be listed and counted, but there is nothing on a page to cover.
    /// The editor must render those as list-only rows rather than silently dropping them.
    public init?(detected: DetectedPII, padding: CGFloat = 0.004, style: RedactionStyle = .solidBar) {
        guard detected.span.hasGeometry else { return nil }
        var region = RedactionRegion(visionBoundingBox: detected.span.boundingBox, style: style)
        region.rect = region.rect.insetBy(dx: -padding, dy: -padding).clampedToUnitSquare()
        guard !region.rect.isEmpty else { return nil }
        self = region
    }

    /// A region from a rectangle the user drew, expressed in the *displayed* image's own
    /// coordinates (top-left origin, points), normalised against `imageSize`.
    ///
    /// Manual drawing is where hand-rolled maths usually creeps in. Feature code should convert
    /// gesture points into the image's frame and then call this, rather than normalising inline.
    public init?(userDrawnRect rect: CGRect, in imageSize: CGSize, style: RedactionStyle = .solidBar) {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        let normalised = CGRect(
            x: rect.minX / imageSize.width,
            y: rect.minY / imageSize.height,
            width: rect.width / imageSize.width,
            height: rect.height / imageSize.height
        ).standardized.clampedToUnitSquare()
        guard !normalised.isEmpty else { return nil }
        self.init(rect: normalised, style: style)
    }

    /// The region in points for a view of `size`, top-left origin — ready for SwiftUI `.offset`
    /// or a `Path`, with no further flipping.
    ///
    /// Distinct from Core's `pixelRect(in:)`, which rounds outward to whole pixels because it is
    /// feeding a pixel buffer. Display wants the exact fractional rect; rounding it would make the
    /// preview disagree with the export by up to a pixel at every zoom level.
    public func displayRect(in size: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * size.width,
            y: rect.minY * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }
}

extension CGRect {
    /// Clips to 0...1 in both axes. Used after any inset so padding cannot escape the page.
    func clampedToUnitSquare() -> CGRect {
        standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}
