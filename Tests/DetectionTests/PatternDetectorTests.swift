import XCTest
@testable import RedactApp

/// True positives: everything the pattern layer is required to find.
final class PatternDetectorTests: XCTestCase {

    private let detector = PatternDetector()

    // MARK: - Helpers

    /// Detects in a short sentence so lookarounds are exercised with real neighbours rather
    /// than string boundaries — bare values hide off-by-one bugs at the edges.
    private func kinds(in value: String, context: String = "Reference %@ noted.") -> [PIIKind] {
        let text = context.replacingOccurrences(of: "%@", with: value)
        return detector.detect(in: text).map(\.kind)
    }

    private func assertDetects(
        _ value: String,
        as kind: PIIKind,
        context: String = "Reference %@ noted.",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let text = context.replacingOccurrences(of: "%@", with: value)
        let hits = detector.detect(in: text)
        guard let hit = hits.first(where: { $0.kind == kind }) else {
            XCTFail("expected \(kind) in \"\(text)\", got \(hits.map(\.kind))", file: file, line: line)
            return
        }
        XCTAssertEqual(hit.span.text, value, file: file, line: line)
        XCTAssertEqual(
            (text as NSString).substring(with: hit.span.nsRange), value,
            "span offsets must select exactly the matched text", file: file, line: line
        )
    }

    // MARK: - Indian identifiers

    func testDetectsVerhoeffValidAadhaar() {
        for number in DetectionFixtures.validAadhaar {
            assertDetects(number, as: .aadhaar)
        }
    }

    func testDetectsGroupedAadhaar() {
        assertDetects("2345 6789 0124", as: .aadhaar)
        assertDetects("2345-6789-0124", as: .aadhaar)
    }

    func testDetectsPAN() {
        for pan in DetectionFixtures.validPAN {
            assertDetects(pan, as: .pan)
        }
    }

    func testDetectsGSTIN() {
        for gstin in DetectionFixtures.validGSTIN {
            assertDetects(gstin, as: .gstin)
        }
    }

    /// A GSTIN contains a PAN. Exactly one detection must survive, and it must be the GSTIN —
    /// otherwise the review list shows the same characters twice under contradictory labels.
    func testGSTINWinsOverTheEmbeddedPAN() {
        let hits = detector.detect(in: "Employer GSTIN: 27ABCDE1234F1Z0")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.kind, .gstin)
    }

    func testDetectsIFSC() {
        for ifsc in DetectionFixtures.validIFSC {
            assertDetects(ifsc, as: .ifsc)
        }
    }

    // MARK: - Cards

    func testDetectsLuhnValidCardsOfEveryPermittedLength() {
        for card in DetectionFixtures.luhnValidCards {
            assertDetects(card, as: .creditCard, context: "Paid with %@ today.")
        }
    }

    func testDetectsGroupedCardWithoutMistakingItForAadhaar() {
        let hits = detector.detect(in: "Card on file: 4539 2415 9206 6114")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.kind, .creditCard)
        XCTAssertEqual(hits.first?.span.text, "4539 2415 9206 6114")
    }

    // MARK: - Contact details

    func testDetectsEmails() {
        for email in DetectionFixtures.validEmails {
            assertDetects(email, as: .email, context: "Write to %@ for queries.")
        }
    }

    func testDetectsIndianPhoneNumbers() {
        for phone in DetectionFixtures.validIndianPhones {
            assertDetects(phone, as: .phone, context: "Call %@ before noon.")
        }
    }

    func testDetectsInternationalPhoneNumbers() {
        for phone in DetectionFixtures.validInternationalPhones {
            assertDetects(phone, as: .phone, context: "Call %@ before noon.")
        }
    }

    // MARK: - Date of birth

    /// The label is what makes a date personal, so the label is what we require —
    /// but the redacted span is the value, not the words "Date of Birth".
    func testDetectsLabelledBirthDatesAndRedactsOnlyTheValue() {
        for text in ["Date of Birth: 12/04/1991", "D.O.B. 12-04-1991", "DOB: 1991-04-12",
                     "Born on 12 April 1991"] {
            let hits = detector.detect(in: text)
            XCTAssertEqual(hits.count, 1, "expected one hit in \"\(text)\"")
            XCTAssertEqual(hits.first?.kind, .dateOfBirth, "in \"\(text)\"")
            XCTAssertFalse(hits.first?.span.text.lowercased().contains("birth") ?? true,
                           "the label must not be part of the redacted span")
        }
    }

    // MARK: - Whole document

    func testMixedDocumentYieldsExactlyTheExpectedKinds() {
        let hits = detector.detect(in: DetectionFixtures.mixedDocument)
        let found = Set(hits.map(\.kind))
        let expected: Set<PIIKind> = [
            .aadhaar, .pan, .gstin, .ifsc, .creditCard, .email, .phone, .dateOfBirth,
        ]
        XCTAssertEqual(found, expected, "detected \(hits.map { "\($0.kind): \($0.span.text)" })")
        XCTAssertEqual(hits.count, expected.count, "no kind should fire twice on this document")
    }

    /// Results arrive in document order so the editor can walk them top to bottom.
    func testResultsAreOrderedByPositionAndDoNotOverlap() {
        let hits = detector.detect(in: DetectionFixtures.mixedDocument)
        XCTAssertEqual(hits.map(\.span.utf16Range.lowerBound),
                       hits.map(\.span.utf16Range.lowerBound).sorted())
        for (a, b) in zip(hits, hits.dropFirst()) {
            XCTAssertLessThanOrEqual(a.span.utf16Range.upperBound, b.span.utf16Range.lowerBound)
        }
    }

    func testEveryDetectionSelectsItsOwnTextExactly() {
        let source = DetectionFixtures.mixedDocument as NSString
        for hit in detector.detect(in: DetectionFixtures.mixedDocument) {
            XCTAssertEqual(source.substring(with: hit.span.nsRange), hit.span.text)
        }
    }

    func testEmptyInputIsHandled() {
        XCTAssertTrue(detector.detect(in: "").isEmpty)
    }
}
