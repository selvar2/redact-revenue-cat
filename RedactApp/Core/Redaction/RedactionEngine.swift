import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import PDFKit
import UIKit

/// Destroys content in images and PDFs.
///
/// The contract of every method here is stronger than "the content is hidden": the bytes returned
/// are a **new file built from a pixel buffer that never contained the redacted content in a
/// recoverable form**, carrying no metadata. There is no layer to remove, no annotation to delete,
/// no text object to extract, and no EXIF/GPS block to read.
///
/// Everything is `nonisolated` and takes and returns `Sendable` values (`Data` in, `Data` out), so
/// callers run it off the main actor with `Task.detached` or inside an actor without smuggling
/// `CGImage`/`PDFDocument` across isolation boundaries. Those types stay inside a single function
/// body by design.
public enum RedactionEngine {

    // MARK: - Images

    /// Applies `regions` to image data and returns a newly encoded, metadata-free image.
    ///
    /// How the guarantee is met, step by step:
    /// 1. The source is decoded to a raw pixel buffer. Nothing from the container carries forward.
    /// 2. Stored EXIF orientation is baked into the pixels, so the buffer is upright and region
    ///    coordinates mean what the editor showed the user.
    /// 3. Each region is filled with an opaque constant using `.copy` blending — the destination
    ///    pixels are *replaced*, not blended over, so no trace of the original survives even at
    ///    fractional alpha.
    /// 4. The buffer is re-encoded through `MetadataStripper`'s writer, which is handed the pixels
    ///    and an orientation tag and nothing else.
    ///
    /// - Parameters:
    ///   - data: Source image data in any format ImageIO can decode.
    ///   - regions: Regions to destroy, normalised `0...1` with a top-left origin.
    ///   - format: Encoding for the output. PNG by default; a lossy re-encode of a document is a
    ///     legibility regression, not a size optimisation.
    public static func redactedImageData(
        from data: Data,
        regions: [RedactionRegion],
        format: RedactedImageFormat = .png
    ) throws -> Data {
        let decoded = try MetadataStripper.decodeImage(data)
        let upright = try bakeOrientation(decoded)
        let redacted = try burnBars(regions, into: upright)

        // Orientation is `.up` because it is now baked into the pixels. Writing the source tag here
        // would rotate the export a second time.
        return try MetadataStripper.encode(redacted, orientation: .up, format: format)
    }

    // MARK: - PDFs

    /// Applies page-scoped redactions to a PDF and returns a new, metadata-free document.
    ///
    /// **Every page carrying a redaction is rasterised in full and rebuilt as an image page.**
    ///
    /// The tradeoff is real and deliberate: that page loses selectable text, copy-paste, reflow, and
    /// text-layer accessibility for *all* of its content, not just the redacted spans. We accept it
    /// because the alternatives do not actually destroy anything:
    ///
    /// - A `PDFAnnotation` black square is drawn *above* the text object. `pdftotext`, text
    ///   selection, or deleting the annotation recovers the original. This is the exact failure that
    ///   has leaked sealed filings at courts and law firms, and `IrreversibilityTests` includes it
    ///   as a control case that must fail.
    /// - Editing the content stream to delete only the covered glyphs requires resolving every font,
    ///   encoding, and text-positioning operator correctly. Any operator we mishandle leaves the
    ///   glyph in place, and the failure is silent — the user sees a clean page and ships a leak.
    /// - Rasterising only the region and splicing it into the existing stream still leaves the
    ///   original text object in the stream underneath.
    ///
    /// Losing selectable text on a page is a visible, understandable cost. Leaving recoverable PII
    /// is an invisible, catastrophic one. Pages with no regions are copied through untouched and
    /// keep their text.
    ///
    /// - Important: A pass-through page is inserted **verbatim**. It keeps its original content
    ///   stream *and* any annotations it already carried. If the source PDF was previously
    ///   "redacted" by another tool drawing black `PDFAnnotation` squares, those squares remain
    ///   removable overlays on any page the user did not redact here — the recipient can delete
    ///   them in Preview and read the text underneath. This engine never *creates* such an overlay,
    ///   but it does not currently flatten inherited ones. Redacting a page (any region on it)
    ///   rasterises it and destroys the problem for that page.
    ///
    /// - Parameters:
    ///   - data: Source PDF data.
    ///   - redactions: Regions per page. Page indices are zero-based.
    ///   - rasterScale: Pixels per point when rasterising. 2.0 keeps small print legible on Retina
    ///     displays without an unreasonable file size.
    public static func redactedPDFData(
        from data: Data,
        redactions: [PageRedaction],
        rasterScale: CGFloat = 2
    ) throws -> Data {
        guard let source = PDFDocument(data: data) else { throw RedactionError.unreadablePDF }

        var regionsByPage: [Int: [RedactionRegion]] = [:]
        for redaction in redactions {
            guard redaction.pageIndex >= 0, redaction.pageIndex < source.pageCount else {
                throw RedactionError.pageIndexOutOfRange(redaction.pageIndex)
            }
            regionsByPage[redaction.pageIndex, default: []] += redaction.regions
        }

        let output = PDFDocument()
        for index in 0..<source.pageCount {
            guard let page = source.page(at: index) else {
                throw RedactionError.pdfPageRebuildFailed(pageIndex: index)
            }

            let regions = regionsByPage[index] ?? []
            if regions.isEmpty {
                output.insert(page, at: output.pageCount)
                continue
            }

            let flattened = try rasterisedPage(page, regions: regions, scale: rasterScale)
            guard let rebuilt = PDFPage(image: flattened) else {
                throw RedactionError.pdfPageRebuildFailed(pageIndex: index)
            }
            output.insert(rebuilt, at: output.pageCount)
        }

        // Both PDF paths share one metadata implementation so neither can drift: clearing
        // `documentAttributes` in place covers /Info but not the catalog's XMP packet, which
        // survives re-serialisation of the same document object.
        let clean = MetadataStripper.metadataFreeCopy(of: output)
        guard let result = clean.dataRepresentation() else { throw RedactionError.encodingFailed }
        return result
    }

    // MARK: - Rasterisation

    /// Renders a page to pixels, burns the bars in, and returns an image sized to the original page
    /// in points so the rebuilt page keeps its dimensions.
    private static func rasterisedPage(
        _ page: PDFPage,
        regions: [RedactionRegion],
        scale: CGFloat
    ) throws -> UIImage {
        let box = page.bounds(for: .mediaBox)
        // A page rotated 90° or 270° presents transposed dimensions; `thumbnail(of:for:)` honours
        // the rotation, so the requested size must be transposed to match.
        let isTransposed = abs(page.rotation) % 180 == 90
        let pointSize = isTransposed
            ? CGSize(width: box.height, height: box.width)
            : box.size

        guard pointSize.width > 0, pointSize.height > 0 else {
            throw RedactionError.rasterisationFailed
        }

        let pixelSize = CGSize(
            width: (pointSize.width * scale).rounded(),
            height: (pointSize.height * scale).rounded()
        )
        let rendered = page.thumbnail(of: pixelSize, for: .mediaBox)
        guard let renderedPixels = rendered.cgImage else { throw RedactionError.rasterisationFailed }

        let redacted = try burnBars(regions, into: renderedPixels)
        return UIImage(cgImage: redacted, scale: scale, orientation: .up)
    }

    // MARK: - Pixel destruction

    /// Fills each region with an opaque constant, replacing the destination pixels outright.
    private static func burnBars(_ regions: [RedactionRegion], into image: CGImage) throws -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        let context = try makeContext(size: size)
        context.draw(image, in: CGRect(origin: .zero, size: size))

        // `.copy` rather than the default `.normal`: normal blending would honour a source alpha,
        // and a bar that is 99% opaque still leaks the glyph underneath it. Copy overwrites.
        context.setBlendMode(.copy)

        for region in regions {
            guard region.style.securityLevel == .irreversible else {
                // Unreachable while `RedactionStyle` has one case. It is a compile-time-cheap guard
                // that a future `.pixelate` cannot silently enter the destroy path.
                throw RedactionError.insecureStyleRejected
            }
            let rect = region.pixelRect(in: size)
            guard !rect.isEmpty else { continue }

            switch region.style {
            case .solidBar(let ink):
                let components = ink.sRGBComponents
                context.setFillColor(
                    red: components.red,
                    green: components.green,
                    blue: components.blue,
                    alpha: components.alpha
                )
            }
            // Flip to CoreGraphics' bottom-left origin. `RedactionRegion` is top-left by contract.
            context.fill(
                CGRect(
                    x: rect.minX,
                    y: size.height - rect.maxY,
                    width: rect.width,
                    height: rect.height
                )
            )
        }

        guard let result = context.makeImage() else { throw RedactionError.rasterisationFailed }
        return result
    }

    /// Rewrites the pixel buffer so that stored EXIF orientation becomes the actual layout.
    ///
    /// Region coordinates come from what the user saw in the editor, which is the *oriented* image.
    /// Without this, a bar placed over a phone number in a sideways-shot photo lands on empty margin
    /// in the export — a silent, total failure of the product's one promise.
    private static func bakeOrientation(_ decoded: MetadataStripper.DecodedImage) throws -> CGImage {
        guard decoded.orientation != .up else { return decoded.image }

        // Core Image owns the correct matrix for all eight EXIF cases; deriving them by hand is a
        // well-known source of off-by-one-mirror bugs.
        let oriented = CIImage(cgImage: decoded.image).oriented(decoded.orientation)
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let result = ciContext.createCGImage(oriented, from: oriented.extent, format: .RGBA8, colorSpace: colorSpace)
        else { throw RedactionError.rasterisationFailed }
        return result
    }

    private static func makeContext(size: CGSize) throws -> CGContext {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw RedactionError.unsupportedColorSpace
        }
        guard
            let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw RedactionError.rasterisationFailed }
        return context
    }
}
