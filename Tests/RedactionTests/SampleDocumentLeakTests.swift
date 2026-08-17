import CoreGraphics
import Foundation
import ImageIO
import UIKit
import Vision
import XCTest

@testable import RedactApp

/// The whole pipeline, end to end, judged by re-reading our own output.
///
/// `IrreversibilityTests` proves the *engine* destroys the regions it is handed.
/// `ClassifierGeometryTests` proves the classifier's arithmetic is self-consistent. Neither could
/// see the two failures that actually shipped, because both live in the seams between components:
///
/// 1. The employee's name was never detected at all — `NLTagger` does not tag `Ananya Mehra`, and
///    the `Employee` label was on its own OCR line where no single-line detector could reach it.
/// 2. Sub-line geometry was interpolated by character *count*, so on `Date of Birth: 14/03/1994`
///    the bar started a glyph late and left the leading `1` of the date in plain sight.
///
/// So this test inspects none of our data structures. It renders the bundled sample, runs the real
/// recogniser, classifier, region projection and engine, then attacks the exported pixels with
/// Vision the way an adversary would — including asking whether any *fragment* of a secret
/// survived at the edge of a bar, which whole-string matching cannot see.
///
/// Controls against vacuity: OCR must recover every secret from the unredacted render, and the
/// classifier must find each named secret by its own text (not merely produce a detection of the
/// right `PIIKind`, which a false positive elsewhere on the page would satisfy).
final class SampleDocumentLeakTests: XCTestCase {

    /// Every value on the sample page that must not survive export. All are fictional — see
    /// `SampleDocument`, where each is declared as a named constant for exactly this kind of audit.
    private static let secrets = [
        "Ananya Mehra",
        "AZZPQ4821K",
        "9999 8888 7779",
        "ananya.mehra@example.com",
        "ZZZZ0123456",
        "14/03/1994",
        "+91 90000 12345",
    ]

    // MARK: - Control 1: the attack can read the page at all

    func testOCRRecoversEverySecretFromTheUnredactedSample() throws {
        let recognised = try Self.ocrText(of: SampleDocument.render())
        for secret in Self.secrets {
            XCTAssertTrue(
                recognised.contains(Self.collapsed(secret)),
                """
                OCR could not read "\(secret)" from the *unredacted* sample, so this file cannot \
                detect a leak of it. Recognised: \(recognised)
                """
            )
        }
    }

    // MARK: - Control 2: every named secret is actually detected

    /// Asserted by text, not by kind. The first version of this test asked only whether *a*
    /// `.personName` detection existed, and passed while the employee's name went unredacted —
    /// the assertion was satisfied by a false positive on the word "August" in the page title.
    func testEverySampleSecretIsDetectedByItsOwnText() async throws {
        let run = try await Self.pipeline()
        let detected = run.detections.map { Self.collapsed($0.span.text) }

        for secret in Self.secrets {
            let needle = Self.collapsed(secret)
            XCTAssertTrue(
                detected.contains { $0.contains(needle) },
                """
                "\(secret)" is printed on the sample and was never detected, so nothing will cover \
                it. Detected: \(run.detections.map { "\($0.kind):\($0.span.text)" })
                """
            )
        }
    }

    // MARK: - The claim

    /// Everything the app told the user it removed must be unrecoverable from the exported file.
    func testNothingTheAppClaimsToHaveRemovedSurvivesExport() async throws {
        let run = try await Self.pipeline()
        XCTAssertEqual(run.regions.count, run.detections.count,
                       "a detection with OCR geometry produced no redaction region")

        let recognised = try Self.ocrText(of: run.exported)

        for detection in run.detections {
            let needle = Self.collapsed(detection.span.text)
            guard needle.count >= 4 else { continue }  // too short to tell from page noise
            XCTAssertFalse(
                recognised.contains(needle),
                """
                "\(detection.span.text)" (\(detection.kind)) was reported as removed but is still \
                readable in the export. Recognised: \(recognised)
                """
            )
        }
    }

    /// A bar one glyph too narrow still leaks — the leading digit of a date of birth cuts a guess
    /// from thousands of candidates to dozens — and **OCR cannot see that failure**.
    ///
    /// This was measured, not assumed: with the old character-count geometry the export visibly
    /// renders `Date of Birth: 1` and `IFSC: Z`, and Vision still reports the line as
    /// `Date of Birth:` because it discards a lone glyph stranded against a black bar. Every
    /// text-level assertion in this file passes on that image. So the oracle here is pixels.
    ///
    /// Ground truth is Vision's own per-character measurement of the source line
    /// (``TextSpan/characterBoxes``) — obtained independently of whatever projection the
    /// classifier chose. Every pixel of the secret's true footprint must be one flat colour in the
    /// export: paper showing through anywhere inside it means part of the secret was left on the
    /// page.
    func testEveryPixelOfASecretIsCoveredInTheExport() async throws {
        let run = try await Self.pipeline()
        let image = try Self.pixels(of: run.exported)

        var checked = 0
        for detection in run.detections {
            guard let line = run.lines.first(where: {
                $0.utf16Range.lowerBound <= detection.span.utf16Range.lowerBound
                    && $0.utf16Range.upperBound >= detection.span.utf16Range.upperBound
            }) else { continue }

            let local = (detection.span.utf16Range.lowerBound - line.utf16Range.lowerBound)
                ..< (detection.span.utf16Range.upperBound - line.utf16Range.lowerBound)
            guard let truth = line.measuredBox(forLocalRange: local) else { continue }
            checked += 1

            let footprint = TextSpan(text: detection.span.text, utf16Range: local, boundingBox: truth)
                .rect(in: CGSize(width: image.width, height: image.height))
                .insetBy(dx: 1, dy: 1)  // ignore the antialiased rim of the glyph run
            guard footprint.width > 2, footprint.height > 2 else { continue }

            let samples = Self.sample(image, in: footprint)
            let distinct = Set(samples)
            XCTAssertEqual(
                distinct.count, 1,
                """
                "\(detection.span.text)" (\(detection.kind)) is not fully covered in the export: \
                \(distinct.count) distinct colours inside the area Vision measured for it, so some \
                of the original page is still showing through the bar. Colours: \(distinct)
                """
            )
        }

        XCTAssertGreaterThan(checked, 0, """
            No detection carried per-character measurements, so this test asserted nothing. That \
            means TextRecogniser stopped populating TextSpan.characterBoxes — fix that rather than \
            this test, because without it the classifier is back to interpolating geometry.
            """)
    }

    // MARK: - The real pipeline

    private struct Run {
        let lines: [TextSpan]
        let detections: [DetectedPII]
        let regions: [RedactionRegion]
        let exported: Data
    }

    private static func pipeline() async throws -> Run {
        let source = SampleDocument.render()
        let recognised = try await TextRecogniser().recognise(imageData: source)
        XCTAssertFalse(recognised.isEmpty, "the recogniser read nothing from the sample")

        let detections = try await HeuristicClassifier().classify(recognised.spans)
        let regions = detections.compactMap { RedactionRegion(detected: $0) }
        let exported = try RedactionEngine.redactedImageData(
            from: source, regions: regions, format: .png
        )
        return Run(lines: recognised.spans, detections: detections,
                   regions: regions, exported: exported)
    }

    // MARK: - OCR attack

    private static func ocrText(of data: Data) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0

        let handler = VNImageRequestHandler(data: data, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        return collapsed(observations.compactMap { $0.topCandidates(1).first?.string }.joined())
    }

    // MARK: - Pixel attack

    private struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]  // RGBA, premultiplied-last, row-major
    }

    private struct Colour: Hashable, CustomStringConvertible {
        let red: UInt8, green: UInt8, blue: UInt8
        var description: String { "#\(String(format: "%02X%02X%02X", red, green, blue))" }
    }

    private static func pixels(of data: Data) throws -> Bitmap {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw XCTSkip("the export could not be decoded for pixel inspection")
        }

        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw XCTSkip("could not create a bitmap context for pixel inspection")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Bitmap(width: width, height: height, bytes: bytes)
    }

    /// A grid of samples across `rect`, dense enough that a single uncovered character — roughly
    /// a twelfth of a date-of-birth run — cannot fall between two probes.
    private static func sample(_ bitmap: Bitmap, in rect: CGRect) -> [Colour] {
        let columns = 60, rows = 6
        var colours: [Colour] = []
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                let x = Int(rect.minX + rect.width * (CGFloat(column) + 0.5) / CGFloat(columns))
                let y = Int(rect.minY + rect.height * (CGFloat(row) + 0.5) / CGFloat(rows))
                guard (0 ..< bitmap.width).contains(x), (0 ..< bitmap.height).contains(y) else { continue }
                let offset = (y * bitmap.width + x) * 4
                colours.append(Colour(red: bitmap.bytes[offset],
                                      green: bitmap.bytes[offset + 1],
                                      blue: bitmap.bytes[offset + 2]))
            }
        }
        return colours
    }

    /// Whitespace is removed on both sides of every comparison so an OCR reading of
    /// "Ananya Mehra" as "AnanyaMehra" — or the reverse — still counts as a leak.
    private static func collapsed(_ string: String) -> String {
        string.filter { !$0.isWhitespace }
    }
}
