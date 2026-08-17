import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Removes everything about a file that is not its visible content.
///
/// A redacted document that still carries its EXIF block leaks the capture time, the device, and —
/// via the GPS dictionary — the coordinates of the desk it was photographed on. That is a worse leak
/// than the text we just destroyed, because the user believes the file is now safe.
///
/// The strategy throughout is **rebuild, never edit**. We decode the pixels (or the page tree) and
/// write a new file from scratch, so metadata is dropped by construction rather than by remembering
/// to delete each key. Deny-lists of keys go stale the moment a new SDK adds a dictionary; a
/// rebuild cannot.
public enum MetadataStripper {

    // MARK: - Images

    /// Re-encodes image data with no metadata except display orientation.
    ///
    /// Dropped: EXIF, GPS, TIFF, IPTC, XMP, Photoshop/IRB, MakerNote, ICC-embedded comments, and any
    /// auxiliary images (embedded thumbnails, depth and matte channels). None of these are carried
    /// forward, because only the primary `CGImage` is passed to the destination.
    ///
    /// Kept: `kCGImagePropertyOrientation`, so a photo taken sideways still displays the right way
    /// up. Orientation says nothing about the user; dropping it would silently rotate their export.
    ///
    /// - Note: `RedactionEngine` does not call this afterwards as a cleanup step — it writes through
    ///   the same private writer, so a redacted export is never metadata-bearing even for an instant.
    public static func strippedImageData(
        _ data: Data,
        format: RedactedImageFormat = .png
    ) throws -> Data {
        let decoded = try decodeImage(data)
        return try encode(decoded.image, orientation: decoded.orientation, format: format)
    }

    /// Every metadata dictionary present in image data, by key.
    ///
    /// Exposed so tests and the audit log can assert on real file contents rather than trusting that
    /// the strip ran. `strippedImageData` output must contain no `Exif`/`GPS`/`IPTC`/`XMP` key.
    public static func metadataDictionaryNames(in data: Data) -> Set<String> {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return [] }

        // Only the container dictionaries count as metadata; scalar keys such as PixelWidth,
        // PixelHeight, ColorModel, and Orientation describe the pixels themselves.
        return Set(properties.filter { $0.value is [String: Any] }.keys)
    }

    /// Metadata dictionaries that must never appear at all in an export. Any key inside one of these
    /// identifies the user, the device, or the place — none of it is derivable from the pixels.
    private static let forbiddenDictionaries: Set<String> = [
        kCGImagePropertyGPSDictionary as String,
        kCGImagePropertyExifAuxDictionary as String,
        kCGImagePropertyIPTCDictionary as String,
        "{XMP}",
        "{Photoshop}",
        "{MakerApple}"
    ]

    /// Keys ImageIO **synthesises** on every write from the pixel buffer itself, whatever the caller
    /// passes. They describe the image we just encoded, not the file we decoded, so their presence
    /// in an export is not a leak — asserting on the `{Exif}`/`{TIFF}` container *names* would be an
    /// assertion no encoder output can ever satisfy. Verified empirically: encoding a freshly
    /// created 10x10 `CGImage` with only `kCGImagePropertyOrientation` still yields both blocks.
    /// See `docs/memory/gotchas/imageio-synthesises-exif-tiff.md`.
    private static let synthesisedKeys: [String: Set<String>] = [
        kCGImagePropertyExifDictionary as String: [
            kCGImagePropertyExifColorSpace as String,
            kCGImagePropertyExifPixelXDimension as String,
            kCGImagePropertyExifPixelYDimension as String
        ],
        kCGImagePropertyTIFFDictionary as String: [
            kCGImagePropertyTIFFOrientation as String,
            kCGImagePropertyTIFFXResolution as String,
            kCGImagePropertyTIFFYResolution as String,
            kCGImagePropertyTIFFResolutionUnit as String,
            kCGImagePropertyTIFFPhotometricInterpretation as String,
            kCGImagePropertyTIFFCompression as String
        ]
    ]

    /// Every identifying metadata key present in image data, as `"{Dict}/Key"`.
    ///
    /// This is the assertion surface for tests and the audit log: it reports what actually
    /// identifies the user rather than which container dictionaries ImageIO happened to emit. An
    /// empty result means the file carries nothing beyond the pixel-derived keys above.
    public static func identifyingMetadataKeys(in data: Data) -> Set<String> {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return [] }

        var offenders: Set<String> = []
        for (name, value) in properties {
            guard let dictionary = value as? [String: Any] else { continue }
            if forbiddenDictionaries.contains(name) {
                offenders.formUnion(dictionary.keys.map { "\(name)/\($0)" })
            } else if let allowed = synthesisedKeys[name] {
                offenders.formUnion(
                    dictionary.keys.filter { !allowed.contains($0) }.map { "\(name)/\($0)" }
                )
            }
        }
        return offenders
    }

    // MARK: - PDFs

    /// Returns PDF data with the document information dictionary and XMP packet removed.
    ///
    /// Clears every `/Info` entry PDFKit exposes (Title, Author, Subject, Keywords, Creator,
    /// Producer, CreationDate, ModDate) plus the document-level XMP stream, then serialises a fresh
    /// document.
    ///
    /// This is metadata only. It does **not** make the page content safe — text objects under a
    /// drawn shape survive here exactly as they do in any other PDF editor. Destroying content is
    /// `RedactionEngine.redactedPDFData(...)`, and that is the only path an export may use.
    public static func strippedPDFData(_ data: Data) throws -> Data {
        guard let document = PDFDocument(data: data) else { throw RedactionError.unreadablePDF }
        let stripped = metadataFreeCopy(of: document)
        guard let output = stripped.dataRepresentation() else { throw RedactionError.encodingFailed }
        return output
    }

    /// Returns a fresh document containing `document`'s pages and none of its document-level
    /// metadata. Shared with `RedactionEngine` so both paths strip identically and neither can drift.
    ///
    /// Clearing `documentAttributes` alone covers `/Info` but not the catalog's `/Metadata` XMP
    /// packet, which survives re-serialisation of the same document object. Building a new
    /// `PDFDocument` and moving the pages across leaves the old catalog — and therefore the XMP —
    /// behind entirely.
    static func metadataFreeCopy(of document: PDFDocument) -> PDFDocument {
        let rebuilt = PDFDocument()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            rebuilt.insert(page, at: rebuilt.pageCount)
        }
        rebuilt.documentAttributes = [:]
        return rebuilt
    }

    // MARK: - Shared decode / encode

    /// Decode result. Deliberately not `Sendable`: `CGImage` is not, and nothing here crosses an
    /// isolation boundary — every caller decodes, redacts, and re-encodes inside one function body,
    /// and what leaves the module is always `Data`.
    struct DecodedImage {
        let image: CGImage
        let orientation: CGImagePropertyOrientation
    }

    /// Decodes the primary image and its stored orientation, discarding everything else.
    static func decodeImage(_ data: Data) throws -> DecodedImage {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: false
        ]
        guard
            let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary),
            let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        else { throw RedactionError.unreadableImage }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return DecodedImage(
            image: image,
            orientation: CGImagePropertyOrientation(rawValue: raw) ?? .up
        )
    }

    /// The single writer for every raster file this module produces.
    ///
    /// Nothing but the pixels and the orientation tag is handed to the destination, so there is no
    /// path by which source metadata reaches an export.
    static func encode(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation,
        format: RedactedImageFormat
    ) throws -> Data {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output as CFMutableData,
                format.utType.identifier as CFString,
                1,
                nil
            )
        else { throw RedactionError.encodingFailed }

        var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation.rawValue]
        if case .jpeg(let quality) = format {
            properties[kCGImageDestinationLossyCompressionQuality] = max(0, min(1, quality))
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RedactionError.encodingFailed }
        return output as Data
    }
}

extension RedactedImageFormat {
    var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        }
    }
}
