import CoreGraphics
import Foundation

// MARK: - Security level

/// How much protection a redaction style actually provides.
///
/// This exists so that "is this safe?" is a value the compiler and the UI can both read, rather
/// than a claim in a comment. Only `.irreversible` styles may be exposed as redaction in the UI.
public enum RedactionSecurityLevel: Sendable, Hashable {
    /// The original pixels are overwritten with a constant. Nothing about the covered content
    /// survives in the output — not the text, not its shape, not its luminance.
    case irreversible

    /// The output is a lossy *function of* the original pixels. Pixelation and blur fall here:
    /// both are convolutions, both retain low-frequency structure, and both have been inverted in
    /// practice for short known-alphabet strings (account numbers, licence plates, PAN-style IDs)
    /// by rendering candidate strings and matching against the released image. Never use for text.
    case reversible
}

// MARK: - Bar ink

/// The constant colour a solid bar is filled with.
///
/// Not a design token: this is not decoration, it is the value written into the pixel buffer, and
/// it must be fully opaque in a device-independent colour space. `DesignSystem/Tokens.swift` owns
/// how a bar is *previewed* in the editor; this owns what is *burned into the export*.
public enum RedactionBarInk: Sendable, Hashable, CaseIterable {
    case black
    case white

    /// Fully opaque sRGB components. Alpha is deliberately not configurable — a translucent bar
    /// leaves the original luminance recoverable, which is the exact bug this module exists to
    /// prevent.
    public var sRGBComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        switch self {
        case .black: (0, 0, 0, 1)
        case .white: (1, 1, 1, 1)
        }
    }
}

// MARK: - Style

/// The visual treatment applied to a redacted region.
///
/// **v1 ships exactly one case, and that is a decision, not an omission.**
///
/// Pixelate and blur are the two variants users ask for by name. Both are `.reversible`: they are
/// deterministic filters over the original pixels, so the original pixels are still *in* the output,
/// just transformed. For short strings drawn from a known alphabet — which is precisely what PII is —
/// an attacker can render every candidate, apply the same filter, and match. Offering them beside a
/// solid bar in the same picker would imply they are equivalent. They are not, and the product claim
/// in `DEC-001` is that we do this correctly.
///
/// If a future version adds them, it must add them as a separate, explicitly labelled
/// "obscure (not secure)" action, and `securityLevel` must report `.reversible` so no code path can
/// treat them as redaction by accident.
public enum RedactionStyle: Sendable, Hashable {
    /// An opaque bar of a constant colour written directly into the pixel buffer.
    case solidBar(ink: RedactionBarInk)

    /// The default treatment: an opaque black bar.
    public static let solidBar: RedactionStyle = .solidBar(ink: .black)

    public var securityLevel: RedactionSecurityLevel {
        switch self {
        case .solidBar: .irreversible
        }
    }
}

// MARK: - Region

/// A rectangle to destroy, in normalised image coordinates.
///
/// Coordinates are `0...1` with the **origin at the top-left** and y increasing downward — the same
/// convention SwiftUI and UIKit use, so editor geometry maps across without a flip. Vision reports
/// boxes bottom-left-origin; use `init(visionBoundingBox:style:)` to convert.
public struct RedactionRegion: Sendable, Hashable {
    /// Normalised rect, top-left origin.
    public var rect: CGRect
    public var style: RedactionStyle

    public init(rect: CGRect, style: RedactionStyle = .solidBar) {
        self.rect = rect
        self.style = style
    }

    /// Converts a Vision bounding box (normalised, **bottom-left** origin) to a redaction region.
    public init(visionBoundingBox box: CGRect, style: RedactionStyle = .solidBar) {
        self.init(
            rect: CGRect(
                x: box.minX,
                y: 1 - box.maxY,
                width: box.width,
                height: box.height
            ),
            style: style
        )
    }

    /// The region in pixel coordinates for an image of `size`, expanded outward to whole pixels.
    ///
    /// Rounding outward matters: rounding to the nearest pixel can leave a one-pixel sliver of the
    /// original glyph at the edge of the bar, and a sliver of a digit is enough to narrow a guess.
    public func pixelRect(in size: CGSize) -> CGRect {
        let scaled = CGRect(
            x: rect.minX * size.width,
            y: rect.minY * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
        return scaled.integral.intersection(CGRect(origin: .zero, size: size))
    }
}

// MARK: - Page-scoped redactions

/// The regions to destroy on one page of a multi-page document.
public struct PageRedaction: Sendable, Hashable {
    /// Zero-based page index.
    public var pageIndex: Int
    public var regions: [RedactionRegion]

    public init(pageIndex: Int, regions: [RedactionRegion]) {
        self.pageIndex = pageIndex
        self.regions = regions
    }
}

// MARK: - Output format

/// Encoding for exported raster output.
public enum RedactedImageFormat: Sendable, Hashable {
    /// Lossless. The default, because a lossy re-encode of a document is a legibility regression.
    case png
    /// Lossy, for photographs where PNG output would be unreasonably large.
    case jpeg(quality: Double)

    public static let jpeg: RedactedImageFormat = .jpeg(quality: 0.9)
}

// MARK: - Errors

public enum RedactionError: Error, Sendable, Equatable {
    case unreadableImage
    case unsupportedColorSpace
    case rasterisationFailed
    case encodingFailed
    /// A style whose `securityLevel` is not `.irreversible` reached the destroy path.
    case insecureStyleRejected
    case unreadablePDF
    case pageIndexOutOfRange(Int)
    case pdfPageRebuildFailed(pageIndex: Int)
}
