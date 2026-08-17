import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision
import XCTest

@testable import RedactApp

/// The acceptance criterion for F04, and the test the entire product claim rests on.
///
/// It does not inspect our own data structures — a bug in the engine would be a bug in that
/// inspection too. It renders a known secret, runs it through the real export path, and then attacks
/// the output the way an adversary would: Vision OCR for images, `PDFDocument.string` (the
/// `pdftotext` equivalent) for PDFs, and ImageIO property inspection for metadata.
///
/// Each destroy-test is paired with a **control** that runs the naive implementation we are claiming
/// to be better than — a translucent overlay for images, a `PDFAnnotation` square for PDFs — and
/// asserts the secret is still recoverable. Without those controls, a test harness that simply
/// failed to read anything would report a clean pass for a completely broken engine.
final class IrreversibilityTests: XCTestCase {

    /// PAN-shaped: five letters, four digits, one letter. Representative of what this app exists to
    /// destroy, and distinctive enough that a partial OCR match is still a failure.
    private let secret = "ABCDE1234F"

    // MARK: - Control: the OCR attack works at all

    /// If this fails, every "the secret is gone" assertion below is worthless, because the harness
    /// cannot read the secret even when it is in plain sight.
    func testOCRRecoversSecretFromUnredactedImage() throws {
        let fixture = try ImageFixture(secret: secret)
        let recognised = try Self.recognisedText(inImageData: fixture.jpegData)

        XCTAssertTrue(
            recognised.contains(secret),
            """
            OCR could not read the secret from the *unredacted* fixture. The redaction assertions in \
            this file cannot detect a failure until this passes. Recognised: \(recognised)
            """
        )
    }

    /// The deliberately broken implementation: a bar composited at low alpha. Visually it looks like
    /// a redaction in a thumbnail; the pixels underneath are still a function of the original.
    /// This asserts the *naive* approach leaks — proving the test can detect a broken engine.
    func testNaiveOverlayControlStillLeaksSecret() throws {
        let fixture = try ImageFixture(secret: secret)
        let naive = try fixture.overlaidWithoutDestroyingPixels(alpha: 0.12)
        let recognised = try Self.recognisedText(inImageData: naive)

        XCTAssertTrue(
            recognised.contains(secret),
            """
            The naive-overlay control did not leak, so this test cannot distinguish a real redaction \
            from a cosmetic one. Recognised: \(recognised)
            """
        )
    }

    // MARK: - Images

    func testRedactedImageIsUnrecoverableByOCR() throws {
        let fixture = try ImageFixture(secret: secret)

        let output = try RedactionEngine.redactedImageData(
            from: fixture.jpegData,
            regions: [RedactionRegion(rect: fixture.secretRegion)],
            format: .png
        )

        let recognised = try Self.recognisedText(inImageData: output)
        XCTAssertFalse(
            recognised.contains(secret),
            "OCR recovered the secret from redacted output. Recognised: \(recognised)"
        )

        // The label outside the region must survive — a redaction that destroys the whole page is
        // trivially "secure" and useless.
        XCTAssertTrue(
            recognised.contains("PERMANENT"),
            "Content outside the redaction region was destroyed. Recognised: \(recognised)"
        )
    }

    /// Sampling the raw buffer proves the bar is a constant, not a heavy blur that OCR merely failed
    /// to parse. A blur would leave varying pixels and would be attackable offline.
    func testRedactedPixelsAreAConstant() throws {
        let fixture = try ImageFixture(secret: secret)
        let output = try RedactionEngine.redactedImageData(
            from: fixture.jpegData,
            regions: [RedactionRegion(rect: fixture.secretRegion)],
            format: .png
        )

        let samples = try Self.samplePixels(in: output, region: fixture.secretRegion, count: 64)
        XCTAssertFalse(samples.isEmpty, "No pixels sampled inside the redacted region.")
        XCTAssertEqual(
            Set(samples).count,
            1,
            "Redacted region contains \(Set(samples).count) distinct colours; it must be one constant."
        )
        XCTAssertEqual(samples.first, Pixel(red: 0, green: 0, blue: 0, alpha: 255))
    }

    func testMetadataIsStrippedFromRedactedImage() throws {
        let fixture = try ImageFixture(secret: secret)

        // Control: the fixture really does carry the metadata we claim to remove.
        let sourceDictionaries = MetadataStripper.metadataDictionaryNames(in: fixture.jpegData)
        XCTAssertTrue(
            sourceDictionaries.contains(kCGImagePropertyExifDictionary as String),
            "Fixture has no EXIF block, so the strip assertion below proves nothing."
        )
        XCTAssertTrue(
            sourceDictionaries.contains(kCGImagePropertyGPSDictionary as String),
            "Fixture has no GPS block, so the strip assertion below proves nothing."
        )
        XCTAssertFalse(
            MetadataStripper.identifyingMetadataKeys(in: fixture.jpegData).isEmpty,
            "Fixture carries no identifying keys, so the strip assertion below proves nothing."
        )

        let output = try RedactionEngine.redactedImageData(
            from: fixture.jpegData,
            regions: [RedactionRegion(rect: fixture.secretRegion)],
            format: .png
        )

        // Assert on keys, not container names: ImageIO unconditionally synthesises {Exif}
        // (ColorSpace, PixelXDimension, PixelYDimension) and {TIFF} (Orientation) on every write,
        // so a container-name assertion could never pass for any encoder output. What matters is
        // that no key identifying the user, the device, or the place survives.
        let leaked = MetadataStripper.identifyingMetadataKeys(in: output)
        XCTAssertTrue(leaked.isEmpty, "Redacted output still carries metadata: \(leaked.sorted())")
    }

    func testStandaloneMetadataStripRemovesEXIFAndGPS() throws {
        let fixture = try ImageFixture(secret: secret)
        let stripped = try MetadataStripper.strippedImageData(fixture.jpegData, format: .jpeg)

        let leaked = MetadataStripper.identifyingMetadataKeys(in: stripped)
        XCTAssertTrue(leaked.isEmpty, "Stripped image still carries metadata: \(leaked.sorted())")
    }

    // MARK: - PDFs

    /// The control that matters most, because it is what Preview, Markup, and most "redaction" apps
    /// actually do. The text object survives under the annotation and one line of code recovers it.
    func testPDFAnnotationControlStillLeaksSecret() throws {
        let source = try Self.makeTextPDF(secret: secret)
        let annotated = try Self.annotatedWithBlackSquare(source)

        let document = try XCTUnwrap(PDFDocument(data: annotated))
        XCTAssertTrue(
            document.string?.contains(secret) == true,
            """
            The PDFAnnotation control did not leak. This test can no longer prove that our \
            rasterising path is better than drawing a black box.
            """
        )
    }

    func testRedactedPDFHasNoExtractableText() throws {
        let source = try Self.makeTextPDF(secret: secret)
        let sourceDocument = try XCTUnwrap(PDFDocument(data: source))
        XCTAssertTrue(
            sourceDocument.string?.contains(secret) == true,
            "Fixture PDF has no extractable secret; the assertion below proves nothing."
        )

        let output = try RedactionEngine.redactedPDFData(
            from: source,
            redactions: [PageRedaction(pageIndex: 0, regions: [RedactionRegion(rect: Self.pdfSecretRegion)])]
        )

        let redacted = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual(redacted.pageCount, sourceDocument.pageCount)

        let extracted = redacted.string ?? ""
        XCTAssertFalse(
            extracted.contains(secret),
            "Text extraction recovered the secret from the redacted PDF: \(extracted)"
        )
        XCTAssertTrue(
            extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "The rasterised page still carries text objects: \(extracted)"
        )

        // The export path must strip /Info too. The fixture deliberately sets Title
        // "Confidential Filing" and Author "Redact Test Rig"; either would identify the client or
        // the user. `testPDFDocumentMetadataIsRemoved` exercises a different function, so without
        // this the redaction export's own metadata is untested.
        let sourceAttributes = sourceDocument.documentAttributes ?? [:]
        XCTAssertNotNil(
            sourceAttributes[PDFDocumentAttribute.titleAttribute],
            "Fixture PDF has no title, so the assertion below proves nothing."
        )
        let attributes = redacted.documentAttributes ?? [:]
        for key in [
            PDFDocumentAttribute.authorAttribute,
            .titleAttribute,
            .subjectAttribute,
            .creatorAttribute,
            .keywordsAttribute
        ] {
            XCTAssertNil(attributes[key], "Redacted PDF still carries \(key.rawValue).")
        }
    }

    func testRedactedPDFIsUnrecoverableByOCR() throws {
        let source = try Self.makeTextPDF(secret: secret)
        let output = try RedactionEngine.redactedPDFData(
            from: source,
            redactions: [PageRedaction(pageIndex: 0, regions: [RedactionRegion(rect: Self.pdfSecretRegion)])]
        )

        let document = try XCTUnwrap(PDFDocument(data: output))
        let page = try XCTUnwrap(document.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        let rendered = page.thumbnail(
            of: CGSize(width: bounds.width * 3, height: bounds.height * 3),
            for: .mediaBox
        )
        let renderedData = try XCTUnwrap(rendered.pngData())

        let recognised = try Self.recognisedText(inImageData: renderedData)
        XCTAssertFalse(
            recognised.contains(secret),
            "OCR recovered the secret from the rendered redacted PDF page. Recognised: \(recognised)"
        )
    }

    func testPDFDocumentMetadataIsRemoved() throws {
        let source = try Self.makeTextPDF(secret: secret)
        let sourceDocument = try XCTUnwrap(PDFDocument(data: source))
        XCTAssertNotNil(
            (sourceDocument.documentAttributes ?? [:])[PDFDocumentAttribute.titleAttribute],
            "Fixture PDF has no title, so the assertions below prove nothing."
        )

        let stripped = try MetadataStripper.strippedPDFData(source)
        let document = try XCTUnwrap(PDFDocument(data: stripped))

        let attributes = document.documentAttributes ?? [:]
        for key in [
            PDFDocumentAttribute.authorAttribute,
            .titleAttribute,
            .subjectAttribute,
            .creatorAttribute,
            .keywordsAttribute
        ] {
            XCTAssertNil(attributes[key], "PDF still carries \(key.rawValue) after strip.")
        }
    }

    // MARK: - Style safety

    func testOnlyIrreversibleStylesExist() {
        // If a future change adds `.pixelate` or `.blur` without marking it `.reversible` and
        // routing it away from the destroy path, this fails and forces the conversation.
        XCTAssertEqual(RedactionStyle.solidBar.securityLevel, .irreversible)
        for ink in RedactionBarInk.allCases {
            XCTAssertEqual(ink.sRGBComponents.alpha, 1, "Bar ink \(ink) is not fully opaque.")
        }
    }

    // MARK: - OCR attack

    private static func recognisedText(inImageData data: Data) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0

        let handler = VNImageRequestHandler(data: data, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        let joined = observations.compactMap { $0.topCandidates(1).first?.string }.joined()
        // Whitespace is collapsed so an OCR reading of "ABCDE 1234F" still counts as a leak. Both
        // search terms used by callers are whitespace-free for the same reason.
        return joined.filter { !$0.isWhitespace }
    }


    // MARK: - Pixel sampling

    struct Pixel: Hashable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    private static func samplePixels(
        in data: Data,
        region: CGRect,
        count: Int
    ) throws -> [Pixel] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: &buffer,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Inset so the sample never straddles the bar edge, where antialiasing is legitimate.
        let pixels = RedactionRegion(rect: region)
            .pixelRect(in: CGSize(width: width, height: height))
            .insetBy(dx: 3, dy: 3)
        guard !pixels.isEmpty else { return [] }

        let steps = max(1, Int(Double(count).squareRoot()))
        var samples: [Pixel] = []
        for row in 0..<steps {
            for column in 0..<steps {
                let x = Int(pixels.minX) + Int(pixels.width) * column / steps
                // A CGBitmapContext stores row 0 as the top row of the drawn image, which is the
                // same top-left convention `pixelRect(in:)` uses — no flip needed here.
                let y = Int(pixels.minY) + Int(pixels.height) * row / steps
                guard x >= 0, x < width, y >= 0, y < height else { continue }
                let offset = (y * width + x) * 4
                samples.append(
                    Pixel(
                        red: buffer[offset],
                        green: buffer[offset + 1],
                        blue: buffer[offset + 2],
                        alpha: buffer[offset + 3]
                    )
                )
            }
        }
        return samples
    }

    // MARK: - Image fixture

    /// A generated document image containing a known secret, plus EXIF and GPS blocks so metadata
    /// stripping has something real to remove. Nothing is loaded from disk: the fixture is built in
    /// code so the test cannot silently pass against a stale asset.
    struct ImageFixture {
        let jpegData: Data
        /// Normalised, top-left origin, covering the secret with a small margin.
        let secretRegion: CGRect
        private let pixels: CGImage

        private static let size = CGSize(width: 1200, height: 500)
        private static let secretOrigin = CGPoint(x: 60, y: 140)  // CG baseline, bottom-left origin
        private static let fontSize: CGFloat = 84

        init(secret: String) throws {
            let size = Self.size
            let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try XCTUnwrap(
                CGContext(
                    data: nil,
                    width: Int(size.width),
                    height: Int(size.height),
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )

            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(origin: .zero, size: size))

            // Control text, deliberately outside the redaction region.
            _ = try Self.draw("PERMANENT ACCOUNT NUMBER", at: CGPoint(x: 60, y: 340), size: 54, in: context)
            let secretBounds = try Self.draw(secret, at: Self.secretOrigin, size: Self.fontSize, in: context)

            let image = try XCTUnwrap(context.makeImage())
            self.pixels = image

            let padded = secretBounds.insetBy(dx: -10, dy: -10)
            self.secretRegion = CGRect(
                x: padded.minX / size.width,
                y: (size.height - padded.maxY) / size.height,
                width: padded.width / size.width,
                height: padded.height / size.height
            )
            self.jpegData = try Self.encodeWithMetadata(image)
        }

        /// Draws a line of text and returns its bounding box in CG (bottom-left origin) pixels.
        @discardableResult
        private static func draw(
            _ string: String,
            at origin: CGPoint,
            size fontSize: CGFloat,
            in context: CGContext
        ) throws -> CGRect {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
            let attributed = NSAttributedString(
                string: string,
                attributes: [
                    .font: font,
                    .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                    .kern: 2.0
                ]
            )
            let line = CTLineCreateWithAttributedString(attributed)

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

            context.textMatrix = .identity
            context.textPosition = origin
            CTLineDraw(line, context)

            return CGRect(
                x: origin.x,
                y: origin.y - descent,
                width: width,
                height: ascent + descent
            )
        }

        /// JPEG with EXIF, GPS, and TIFF blocks attached — the leak a photo of a redacted document
        /// carries even after the visible content is destroyed.
        private static func encodeWithMetadata(_ image: CGImage) throws -> Data {
            let output = NSMutableData()
            let destination = try XCTUnwrap(
                CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
            )
            let properties: [CFString: Any] = [
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifDateTimeOriginal: "2026:08:17 09:41:00",
                    kCGImagePropertyExifLensModel: "Redact Test Rig"
                ],
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: 12.9716,
                    kCGImagePropertyGPSLatitudeRef: "N",
                    kCGImagePropertyGPSLongitude: 77.5946,
                    kCGImagePropertyGPSLongitudeRef: "E"
                ],
                kCGImagePropertyTIFFDictionary: [
                    kCGImagePropertyTIFFMake: "Redact",
                    kCGImagePropertyTIFFModel: "Fixture"
                ],
                kCGImageDestinationLossyCompressionQuality: 1.0
            ]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw RedactionError.encodingFailed
            }
            return output as Data
        }

        /// The broken implementation this project exists to be better than: a bar composited over
        /// the content at less than full opacity. Used only as a control.
        func overlaidWithoutDestroyingPixels(alpha: CGFloat) throws -> Data {
            let size = CGSize(width: pixels.width, height: pixels.height)
            let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try XCTUnwrap(
                CGContext(
                    data: nil,
                    width: pixels.width,
                    height: pixels.height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            context.draw(pixels, in: CGRect(origin: .zero, size: size))

            let rect = RedactionRegion(rect: secretRegion).pixelRect(in: size)
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: alpha)
            context.fill(
                CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
            )

            let image = try XCTUnwrap(context.makeImage())
            return try MetadataStripper.encode(image, orientation: .up, format: .png)
        }
    }

    // MARK: - PDF fixture

    /// Where the secret sits on the generated PDF page, normalised with a top-left origin.
    private static let pdfSecretRegion = CGRect(x: 0.05, y: 0.10, width: 0.55, height: 0.10)

    private static func makeTextPDF(secret: String) throws -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        // Document-level /Info, not per-page info: `beginPage(pageInfo:)` carries page
        // attributes, which PDFKit never surfaces as `documentAttributes`. Setting it on the
        // format is what actually gives the fixture a Title and Author to strip — without it the
        // metadata assertions would pass against a document that never had metadata.
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Confidential Filing",
            kCGPDFContextAuthor as String: "Redact Test Rig"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        return renderer.pdfData { context in
            context.beginPage()
            let heading = NSAttributedString(
                string: "PERMANENT ACCOUNT NUMBER",
                attributes: [.font: UIFont.boldSystemFont(ofSize: 24)]
            )
            heading.draw(at: CGPoint(x: 36, y: 36))

            let body = NSAttributedString(
                string: secret,
                attributes: [.font: UIFont.boldSystemFont(ofSize: 40)]
            )
            // Matches `pdfSecretRegion`: 0.10 * 792 ≈ 79pt from the top.
            body.draw(at: CGPoint(x: 36, y: 82))
        }
    }

    /// The naive PDF "redaction": a filled black annotation on top of the text. Control only.
    private static func annotatedWithBlackSquare(_ data: Data) throws -> Data {
        let document = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(document.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)

        let region = RedactionRegion(rect: pdfSecretRegion)
        let annotationBounds = CGRect(
            x: region.rect.minX * bounds.width,
            y: bounds.height - (region.rect.maxY * bounds.height),
            width: region.rect.width * bounds.width,
            height: region.rect.height * bounds.height
        )

        let annotation = PDFAnnotation(bounds: annotationBounds, forType: .square, withProperties: nil)
        annotation.color = .black
        annotation.interiorColor = .black
        page.addAnnotation(annotation)

        return try XCTUnwrap(document.dataRepresentation())
    }
}
