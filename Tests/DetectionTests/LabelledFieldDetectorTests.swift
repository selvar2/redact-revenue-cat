import CoreGraphics
import XCTest
@testable import RedactApp

/// Names found by the label beside them rather than by recognising the name.
///
/// The case that forced this detector to exist: `NLTagger` does not tag "Ananya Mehra" on the
/// bundled sample, so the flagship demo exported a payslip that still named the employee. A model
/// that has never seen a name has no way to know it is one; a printed `Employee` label says so
/// regardless of language.
///
/// The risk of a label-driven rule is the opposite failure — bars over job titles and reference
/// codes, which teaches users to switch bars off. Half the tests here are about that.
final class LabelledFieldDetectorTests: XCTestCase {

    // MARK: - Inline

    func testDetectsANameAfterAnInlineLabel() {
        let hits = LabelledFieldDetector().detect(in: "Employee: Ananya Mehra")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.kind, .personName)
        XCTAssertEqual(hits.first?.span.text, "Ananya Mehra")
    }

    /// The span must select the name and nothing else — offsets that include the label or the
    /// space after the colon draw a bar wider than the text it destroys.
    func testTheSpanSelectsExactlyTheName() {
        let line = "Account Holder: Ravi Kumar Iyer"
        guard let hit = LabelledFieldDetector().detect(in: line).first else {
            return XCTFail("no detection")
        }
        XCTAssertEqual((line as NSString).substring(with: hit.span.nsRange), "Ravi Kumar Iyer")
    }

    func testGeometryComesFromTheSuppliedProvider() {
        let box = CGRect(x: 0.2, y: 0.4, width: 0.3, height: 0.02)
        let hits = LabelledFieldDetector().detect(in: "Name: Ananya Mehra") { _ in box }
        XCTAssertEqual(hits.first?.span.boundingBox, box)
    }

    // MARK: - Not names

    func testIgnoresLabelsWhoseValueIsNotAName() {
        let detector = LabelledFieldDetector()
        XCTAssertTrue(detector.detect(in: "Designation: Senior Data Analyst").isEmpty,
                      "a job title is not a name and must not be redacted as one")
        XCTAssertTrue(detector.detect(in: "Employee ID: NWA-2291").isEmpty,
                      "an employee code is not a name")
        XCTAssertTrue(detector.detect(in: "Gross Pay: 1,25,000.00").isEmpty)
        XCTAssertTrue(detector.detect(in: "Bank A/C: 0004 1122 3344").isEmpty)
        XCTAssertTrue(detector.detect(in: "no label here at all").isEmpty)
    }

    func testAValueContainingADigitIsNeverAName() {
        XCTAssertFalse(LabelledFieldDetector.looksLikeAPersonName("Ananya 2 Mehra"))
        XCTAssertFalse(LabelledFieldDetector.looksLikeAPersonName("NWA-2291"))
    }

    func testLabelMatchingIgnoresCaseAndTrailingPunctuation() {
        XCTAssertTrue(LabelledFieldDetector.isNameLabel("Employee"))
        XCTAssertTrue(LabelledFieldDetector.isNameLabel("EMPLOYEE:"))
        XCTAssertTrue(LabelledFieldDetector.isNameLabel(" account holder "))
        XCTAssertFalse(LabelledFieldDetector.isNameLabel("Employee ID"))
        XCTAssertFalse(LabelledFieldDetector.isNameLabel("Designation"))
    }

    // MARK: - Stacked across OCR lines

    /// OCR reads the sample's two-column employee block as a stack of single-line spans, so the
    /// label and its value never appear in the same string. This is the arrangement that shipped
    /// the leak.
    func testClaimsTheLineAfterABareLabel() async throws {
        let lines = ["Employee", "Ananya Mehra", "Designation", "Senior Data Analyst"]
        var spans: [TextSpan] = []
        var offset = 0
        for (index, line) in lines.enumerated() {
            let length = (line as NSString).length
            spans.append(TextSpan(text: line, utf16Range: offset ..< (offset + length),
                                  boundingBox: CGRect(x: 0.1, y: 0.9 - 0.05 * CGFloat(index),
                                                      width: 0.4, height: 0.03)))
            offset += length + 1
        }

        let hits = try await HeuristicClassifier().classify(spans)
        let names = hits.filter { $0.kind == .personName }

        XCTAssertEqual(names.map(\.span.text), ["Ananya Mehra"],
                       "the labelled name must be found, and the job title must not be")
        XCTAssertTrue(names.first?.span.hasGeometry == true,
                      "a name with no box cannot be covered on the page")
    }

    func testABareLabelWithNoFollowingLineIsHarmless() async throws {
        let span = TextSpan(text: "Employee", utf16Range: 0 ..< 8,
                            boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.05))
        let hits = try await HeuristicClassifier().classify([span])
        XCTAssertTrue(hits.filter { $0.kind == .personName }.isEmpty)
    }
}
