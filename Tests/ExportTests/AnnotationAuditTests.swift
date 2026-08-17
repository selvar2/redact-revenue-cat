import CoreGraphics
import Foundation
import PDFKit
import UIKit
import XCTest

@testable import RedactApp

/// The acceptance criteria for the "detect and offer" decision on inherited PDF markup.
///
/// Two failure modes matter here and they pull in opposite directions:
///
/// - **Missing a real fake redaction** ships a document the user believes is safe, with a black box
///   the recipient can delete in Preview.
/// - **Flagging a harmless signature** is worse than it sounds. A warning that fires on every signed
///   contract is a warning users learn to tap through, and they will tap through the one that
///   mattered too. A false positive does not merely annoy — it disarms the true positive.
///
/// So both directions are asserted, and the signature-over-blank-space case is as load-bearing as
/// the black-box case.
final class AnnotationAuditTests: XCTestCase {

    /// PAN-shaped, matching the fixture vocabulary used by `IrreversibilityTests`.
    private let secret = "ABCDE1234F"

    // MARK: - Control: the fixture actually hides text

    /// If the fixture's box is not over the text, every assertion below is vacuous — the audit
    /// would be "correctly" reporting nothing hidden because nothing is hidden.
    func testFixtureBoxActuallyCoversExtractableText() throws {
        let annotated = try Self.pdfWithBlackBoxOverSecret(secret: secret)
        let document = try XCTUnwrap(PDFDocument(data: annotated))
        let page = try XCTUnwrap(document.page(at: 0))
        let annotation = try XCTUnwrap(page.annotations.first)

        let underneath = page.selection(for: annotation.bounds)?.string ?? ""
        XCTAssertTrue(
            underneath.contains(secret),
            """
            The fixture's box does not sit over the secret, so this test file cannot detect an audit \
            that has stopped working. Text found under the box: \(underneath)
            """
        )
    }

    // MARK: - The dangerous case

    func testAuditFlagsBlackBoxOverTextAndReportsHiddenText() throws {
        let annotated = try Self.pdfWithBlackBoxOverSecret(secret: secret)

        let report = try AnnotationAudit.audit(pdfData: annotated)

        XCTAssertFalse(report.isEmpty, "A filled black box over live text was not flagged.")
        XCTAssertEqual(report.flaggedPageIndices, [0])

        let finding = try XCTUnwrap(report.finding(forPage: 0))
        XCTAssertEqual(finding.primaryMarkType, .box)
        XCTAssertGreaterThanOrEqual(
            finding.hiddenCharacterCount,
            secret.count,
            "The audit flagged the page but did not report the text hidden under the box."
        )
        XCTAssertEqual(finding.markRects.count, 1)

        // The reported rect is normalised, top-left origin, and inside the page.
        let rect = try XCTUnwrap(finding.markRects.first)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(rect))
        XCTAssertEqual(rect.minY, Self.secretRegion.minY, accuracy: 0.02,
                       "The mark rect is not in top-left normalised space — a coordinate flip is wrong.")
    }

    // MARK: - The false-positive case

    func testSignatureOverBlankSpaceIsNotFlagged() throws {
        let signed = try Self.pdfWithSignatureInBlankMargin(secret: secret)

        let report = try AnnotationAudit.audit(pdfData: signed)

        XCTAssertTrue(
            report.isEmpty,
            """
            A signature drawn in an empty margin was flagged as a possible fake redaction. False \
            positives here train users to dismiss the warning, which is worse than no warning: the \
            one document that really is leaking gets dismissed too. Flagged pages: \
            \(report.flaggedPageIndices)
            """
        )
        XCTAssertEqual(
            report.benignMarkupPageIndices, [0],
            "The signature should still be recorded as harmless markup, so no copy claims the file has none."
        )
    }

    /// An unfilled rectangle is a frame around text, not a cover over it. Nobody believes the text
    /// inside it is hidden, and warning about it is noise.
    func testUnfilledOutlineOverTextIsNotFlagged() throws {
        let outlined = try Self.pdfWithOutlineOverSecret(secret: secret)

        let report = try AnnotationAudit.audit(pdfData: outlined)

        XCTAssertTrue(report.isEmpty, "An unfilled outline around visible text was flagged as concealing.")
    }

    // MARK: - Making it permanent

    /// The other half of the decision: when the user says "make it permanent", the text under the
    /// box must actually be gone from the exported bytes — not merely covered more convincingly.
    func testFlatteningDestroysTheTextUnderTheBox() throws {
        let annotated = try Self.pdfWithBlackBoxOverSecret(secret: secret)

        let before = try XCTUnwrap(PDFDocument(data: annotated))
        XCTAssertTrue(
            before.string?.contains(secret) == true,
            "The fixture does not leak before flattening, so the assertion below proves nothing."
        )

        // Exactly what `ExportPipeline.pageRedactions(for:flattening:)` builds for a page the user
        // chose to make permanent: a zero-sized region, which asks `RedactionEngine` to rebuild the
        // page from pixels without burning any extra bars.
        let flattened = try RedactionEngine.redactedPDFData(
            from: annotated,
            redactions: [PageRedaction(pageIndex: 0, regions: [ExportPipeline.flattenOnlyRegion])]
        )

        let after = try XCTUnwrap(PDFDocument(data: flattened))
        XCTAssertEqual(after.pageCount, before.pageCount)
        XCTAssertFalse(
            after.string?.contains(secret) == true,
            """
            After making the page permanent, `PDFDocument.string` — the `pdftotext` equivalent — \
            still yields the secret. The box is still a removable overlay.
            """
        )
        XCTAssertTrue(
            (try XCTUnwrap(after.page(at: 0))).annotations.isEmpty,
            "The flattened page still carries the original mark as a separate, removable object."
        )

        // And the audit agrees the file is now clean, which is what the export screen's copy relies on.
        let reaudit = try AnnotationAudit.audit(pdfData: flattened)
        XCTAssertTrue(reaudit.isEmpty)
    }

    /// Leaving the marks alone must be a genuine no-op on the other pages: "leave as is" means the
    /// document goes out unchanged, and the app must not quietly alter it.
    func testLeavingMarksAloneKeepsThePageUntouched() throws {
        let annotated = try Self.pdfWithBlackBoxOverSecret(secret: secret)

        let untouched = try RedactionEngine.redactedPDFData(from: annotated, redactions: [])
        let result = try XCTUnwrap(PDFDocument(data: untouched))

        XCTAssertTrue(
            result.string?.contains(secret) == true,
            "The pass-through path silently changed a page the user asked to leave alone."
        )
        XCTAssertFalse(
            try AnnotationAudit.audit(pdfData: untouched).isEmpty,
            "The audit must keep flagging an untouched document, so no UI can claim it is clean."
        )
    }

    // MARK: - Bad input

    func testAuditRejectsNonPDFData() {
        XCTAssertThrowsError(try AnnotationAudit.audit(pdfData: Data("not a pdf".utf8))) { error in
            XCTAssertEqual(error as? AnnotationAudit.AuditError, .unreadablePDF)
        }
    }

    // MARK: - Fixtures

    /// Where the secret sits on the generated page, normalised with a **top-left** origin.
    private static let secretRegion = CGRect(x: 0.05, y: 0.10, width: 0.55, height: 0.10)

    private static let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

    /// A one-page PDF with a heading and the secret set in large type.
    private static func textPDF(secret: String) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        return renderer.pdfData { context in
            context.beginPage()
            NSAttributedString(
                string: "PERMANENT ACCOUNT NUMBER",
                attributes: [.font: UIFont.boldSystemFont(ofSize: 24)]
            ).draw(at: CGPoint(x: 36, y: 36))

            NSAttributedString(
                string: secret,
                attributes: [.font: UIFont.boldSystemFont(ofSize: 40)]
            ).draw(at: CGPoint(x: 36, y: 82))
        }
    }

    /// Converts a normalised top-left rect to PDF page space (points, bottom-left origin).
    ///
    /// Test-local on purpose: production code must never hand-roll this, and a test that reuses the
    /// production converter cannot catch the production converter being wrong.
    private static func pageRect(_ normalised: CGRect) -> CGRect {
        CGRect(
            x: normalised.minX * pageBounds.width,
            y: pageBounds.height - (normalised.maxY * pageBounds.height),
            width: normalised.width * pageBounds.width,
            height: normalised.height * pageBounds.height
        )
    }

    /// The dangerous fixture: a filled black square drawn over the secret by "another tool".
    private static func pdfWithBlackBoxOverSecret(secret: String) throws -> Data {
        let document = try XCTUnwrap(PDFDocument(data: textPDF(secret: secret)))
        let page = try XCTUnwrap(document.page(at: 0))

        let annotation = PDFAnnotation(bounds: pageRect(secretRegion), forType: .square, withProperties: nil)
        annotation.color = .black
        annotation.interiorColor = .black
        page.addAnnotation(annotation)

        return try XCTUnwrap(document.dataRepresentation())
    }

    /// The harmless fixture: freehand ink low on the page, well clear of any text.
    private static func pdfWithSignatureInBlankMargin(secret: String) throws -> Data {
        let document = try XCTUnwrap(PDFDocument(data: textPDF(secret: secret)))
        let page = try XCTUnwrap(document.page(at: 0))

        // Bottom fifth of the page. The fixture only draws text in the top ~15%, so there is
        // nothing underneath this to recover.
        let signatureBounds = CGRect(x: 60, y: 60, width: 220, height: 70)
        let annotation = PDFAnnotation(bounds: signatureBounds, forType: .ink, withProperties: nil)
        annotation.color = .black

        let path = UIBezierPath()
        path.move(to: CGPoint(x: 70, y: 80))
        path.addCurve(
            to: CGPoint(x: 260, y: 100),
            controlPoint1: CGPoint(x: 120, y: 130),
            controlPoint2: CGPoint(x: 200, y: 60)
        )
        annotation.add(path)
        page.addAnnotation(annotation)

        return try XCTUnwrap(document.dataRepresentation())
    }

    /// A hollow rectangle around the secret — a frame, not a cover.
    private static func pdfWithOutlineOverSecret(secret: String) throws -> Data {
        let document = try XCTUnwrap(PDFDocument(data: textPDF(secret: secret)))
        let page = try XCTUnwrap(document.page(at: 0))

        let annotation = PDFAnnotation(bounds: pageRect(secretRegion), forType: .square, withProperties: nil)
        annotation.color = .clear
        page.addAnnotation(annotation)

        return try XCTUnwrap(document.dataRepresentation())
    }
}
