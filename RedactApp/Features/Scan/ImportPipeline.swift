import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UIKit

/// Turns whatever the user brought in — a VisionKit capture, a photo, a PDF on disk — into a
/// validated ``SessionSource``.
///
/// This sits *in front of* ``DocumentPipeline``, and the split matters. `DocumentPipeline` assumes
/// its source is decodable and non-empty; everything that decides whether that is true, and
/// everything that has to talk to the outside world (security-scoped file URLs, `UIImage` from
/// VisionKit), lives here. So there is exactly one place where a bad file becomes a *message* rather
/// than a crash or an empty editor.
///
/// Two rules shape all of it:
///
/// 1. **Normalise before the session exists, never after.** The bytes handed to
///    `SessionSource` are the bytes Vision reads *and* the bytes `RedactionEngine` later destroys.
///    If those two ever differ, a redaction bar lands in the wrong place and the export leaks. Any
///    resampling therefore happens here, once, before anyone has seen the document.
/// 2. **Pass through when possible.** A JPEG or HEIC from the photo library is handed on untouched.
///    Re-encoding it would change the pixels Vision reads for no benefit, and every re-encode is a
///    chance to drop or rotate something.
public enum ImportPipeline {

    // MARK: - Tuning

    /// Above this many pixels an imported photo is downsampled before it becomes a session source.
    ///
    /// 36 MP is comfortably above every current iPhone sensor (48 MP ProRAW aside) and above a 300
    /// dpi A4 scan, so in practice nothing the app is designed for is touched. It exists for the
    /// outliers — a stitched panorama, a 100 MP scanner output — where decoding the full bitmap
    /// three times over (preview, Vision, export) is the difference between working and being
    /// killed by the memory limit mid-redaction.
    public static let maximumImagePixelCount = 36_000_000

    /// Encoding quality for a page captured by the camera.
    ///
    /// JPEG rather than PNG here specifically because the input is a camera capture: the pixels have
    /// already been through the ISP's lossy pipeline, so a lossless container preserves nothing real
    /// while costing roughly ten times the bytes and the encode time on a multi-page scan. Imported
    /// files are never re-encoded at this quality — they are passed through untouched.
    public static let scannedPageQuality: CGFloat = 0.95

    // MARK: - Origin

    /// Where a document came in from.
    ///
    /// Scan tracks this itself rather than reading `SessionSource.kind`, which cannot distinguish a
    /// camera capture from a photo pick — both are `.image`. It drives the default document title
    /// and nothing else.
    public enum Origin: Sendable, Hashable {
        case camera
        case photoLibrary
        case files

        /// The name a document gets when the user has not named it — which is always, at import.
        ///
        /// Date-stamped rather than "Untitled 3": a library of scans is searched by *when*, and a
        /// counter would require reading the store just to name a thing the user may discard.
        public func defaultTitle(date: Date = .now) -> String {
            let stamp = date.formatted(date: .abbreviated, time: .shortened)
            switch self {
            case .camera:
                return String(localized: "Scan \(stamp)", comment: "Default title for a camera-captured document")
            case .photoLibrary:
                return String(localized: "Photo \(stamp)", comment: "Default title for a document imported from the photo library")
            case .files:
                return String(localized: "Document \(stamp)", comment: "Default title for a document imported from Files")
            }
        }
    }

    // MARK: - Photo library

    /// Validates and, if it is enormous, downsamples an image the user picked.
    ///
    /// HEIC needs no special case: ImageIO decodes it like anything else, and the bytes are handed
    /// on unchanged, so the HEIC is what Vision reads and what the export path redacts.
    public static func makeSource(imageData data: Data) async throws -> SessionSource {
        let limit = maximumImagePixelCount
        return try await Task.detached(priority: .userInitiated) {
            try normalisedImageSource(data, pixelLimit: limit)
        }.value
    }

    // MARK: - Files

    /// Reads a PDF the user picked in the document browser and validates it.
    ///
    /// The URL is security-scoped — it points outside the app container, and reading it without
    /// claiming access fails with a permission error that looks exactly like a corrupt file. The
    /// claim is released in `defer` even on the throwing paths, because leaking scoped URLs
    /// eventually exhausts the sandbox's grant table and every later import fails.
    public static func makeSource(pdfAt url: URL) async throws -> SessionSource {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw ImportError.fileUnreadable
            }
            return try validatedPDFSource(data)
        }.value
    }

    /// Validates PDF bytes already in memory.
    public static func makeSource(pdfData data: Data) async throws -> SessionSource {
        try await Task.detached(priority: .userInitiated) {
            try validatedPDFSource(data)
        }.value
    }

    /// A file's own name, minus the extension, so an imported `Bank statement.pdf` keeps its name in
    /// the library instead of becoming "Document 17 Aug".
    public static func title(forFileAt url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? Origin.files.defaultTitle() : name
    }

    // MARK: - Camera

    /// Packages the pages of a VisionKit capture into a session source.
    ///
    /// A single page becomes an image; two or more become a PDF. That is not cosmetic —
    /// ``SessionSource`` has no multi-image case, and inventing one would mean a second page-indexing
    /// scheme running alongside `PageRedaction.pageIndex`. A PDF already *is* the multi-page
    /// container the rest of the app understands, and `DocumentPipeline` rasterises it back to one
    /// image per page for display.
    ///
    /// `@MainActor` because `UIImage` is not `Sendable` and VisionKit hands its pages over on the
    /// main actor. The images are converted to `Data` here, with a `yield` between pages so the
    /// progress overlay keeps animating, and only `Data` crosses into the detached PDF assembly
    /// (`CLAUDE.md` rule 5 — no `@unchecked Sendable` to get a `UIImage` off the actor).
    @MainActor
    public static func makeSource(scannedPages images: [UIImage]) async throws -> SessionSource {
        guard !images.isEmpty else { throw ImportError.emptyScan }

        var encoded: [Data] = []
        encoded.reserveCapacity(images.count)
        for image in images {
            try Task.checkCancellation()
            guard let jpeg = image.jpegData(compressionQuality: scannedPageQuality) else {
                throw ImportError.encodingFailed
            }
            encoded.append(jpeg)
            await Task.yield()
        }

        if encoded.count == 1 {
            return .image(encoded[0])
        }

        let pages = encoded
        let data = try await Task.detached(priority: .userInitiated) {
            try pdfData(fromPageImages: pages)
        }.value
        return .pdf(data)
    }

    // MARK: - Image normalisation

    private static func normalisedImageSource(_ data: Data, pixelLimit: Int) throws -> SessionSource {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Double,
            let height = properties[kCGImagePropertyPixelHeight] as? Double,
            width > 0, height > 0
        else {
            throw ImportError.unreadableImage
        }

        guard width * height > Double(pixelLimit) else {
            return .image(data)
        }

        // Preserve the aspect ratio while landing under the budget: scaling both edges by
        // sqrt(limit / area) scales the area by exactly limit / area.
        let scale = (Double(pixelLimit) / (width * height)).squareRoot()
        let longestEdge = (max(width, height) * scale).rounded(.down)

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longestEdge,
            // Bakes the EXIF orientation into the pixels. Without it the downsample keeps the
            // orientation *tag* while the caller sees new bytes, and a sideways photo gets its
            // redaction bars a quarter turn out.
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            let reduced = UIImage(cgImage: thumbnail).jpegData(compressionQuality: scannedPageQuality)
        else {
            throw ImportError.unreadableImage
        }
        return .image(reduced)
    }

    // MARK: - PDF

    private static func validatedPDFSource(_ data: Data) throws -> SessionSource {
        guard let document = PDFDocument(data: data) else { throw ImportError.unreadablePDF }
        // `isLocked` is the one that matters: an encrypted-but-unlocked document (the common case
        // for permissions-only encryption) reads fine, while a locked one renders blank pages and
        // would otherwise reach the editor as a document with zero detections and no explanation.
        guard !document.isLocked else { throw ImportError.lockedPDF }
        guard document.pageCount > 0 else { throw ImportError.emptyPDF }
        return .pdf(data)
    }

    /// Assembles JPEG page bytes into a single PDF, one page per image, at 1 point per pixel.
    ///
    /// No resampling: the page box is the image's pixel size, so the PDF carries the captured
    /// resolution and `DocumentPipeline` can rasterise it back at ``DocumentPipeline/pageRasterScale``
    /// without having lost detail in between.
    private static func pdfData(fromPageImages pages: [Data]) throws -> Data {
        var images: [UIImage] = []
        images.reserveCapacity(pages.count)
        for bytes in pages {
            guard let image = UIImage(data: bytes) else { throw ImportError.encodingFailed }
            images.append(image)
        }

        guard let first = images.first else { throw ImportError.emptyScan }
        let firstBounds = CGRect(origin: .zero, size: pixelBounds(of: first))
        let renderer = UIGraphicsPDFRenderer(bounds: firstBounds)

        let data = renderer.pdfData { context in
            for image in images {
                let bounds = CGRect(origin: .zero, size: pixelBounds(of: image))
                context.beginPage(withBounds: bounds, pageInfo: [:])
                image.draw(in: bounds)
            }
        }

        guard !data.isEmpty else { throw ImportError.encodingFailed }
        return data
    }

    /// The image's size in pixels. `UIImage.size` is in points and already accounts for
    /// orientation; multiplying by `scale` gives the captured pixel grid.
    private static func pixelBounds(of image: UIImage) -> CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    // MARK: - Errors

    /// Import failures, each phrased as something the user can act on.
    ///
    /// Every case pairs a description with a recovery suggestion, and `ScanView` shows both —
    /// `CLAUDE.md`'s "no screen can dead-end" applies most sharply here, because this is the first
    /// thing a new user does and a bare "Something went wrong" is where they stop.
    public enum ImportError: Error, Sendable, Equatable, LocalizedError {
        case unreadableImage
        case unreadablePDF
        case lockedPDF
        case emptyPDF
        case emptyScan
        case fileUnreadable
        case encodingFailed
        case cameraUnavailable

        public var errorDescription: String? {
            switch self {
            case .unreadableImage:
                return String(localized: "This image could not be opened.",
                              comment: "Error: the picked photo could not be decoded")
            case .unreadablePDF:
                return String(localized: "This PDF could not be opened.",
                              comment: "Error: the picked file is not a readable PDF")
            case .lockedPDF:
                return String(localized: "This PDF is password-protected.",
                              comment: "Error: the picked PDF is encrypted and locked")
            case .emptyPDF:
                return String(localized: "This PDF has no pages.",
                              comment: "Error: the picked PDF contains zero pages")
            case .emptyScan:
                return String(localized: "No pages were captured.",
                              comment: "Error: the camera scan finished with no pages")
            case .fileUnreadable:
                return String(localized: "This file could not be read.",
                              comment: "Error: the picked file could not be read from disk")
            case .encodingFailed:
                return String(localized: "These pages could not be prepared.",
                              comment: "Error: captured pages could not be encoded")
            case .cameraUnavailable:
                return String(localized: "Document scanning isn’t available on this device.",
                              comment: "Error: VisionKit document scanning is unsupported")
            }
        }

        public var recoverySuggestion: String? {
            switch self {
            case .unreadableImage:
                return String(localized: "Pick a different photo, or take a new one with the camera.",
                              comment: "Recovery: choose another photo")
            case .unreadablePDF, .fileUnreadable:
                return String(localized: "Pick a different file, or photograph the page instead.",
                              comment: "Recovery: choose another file")
            case .lockedPDF:
                return String(localized: "Open it in Files, enter its password and save an unlocked copy, then import that.",
                              comment: "Recovery: unlock the PDF first")
            case .emptyPDF:
                return String(localized: "Pick a file that has at least one page.",
                              comment: "Recovery: choose a non-empty PDF")
            case .emptyScan:
                return String(localized: "Open the camera again and capture at least one page.",
                              comment: "Recovery: rescan")
            case .encodingFailed:
                return String(localized: "Try scanning again, with fewer pages at a time.",
                              comment: "Recovery: retry the scan")
            case .cameraUnavailable:
                return String(localized: "Import a photo or a PDF instead — everything else works the same.",
                              comment: "Recovery: use import instead of the camera")
            }
        }
    }
}
