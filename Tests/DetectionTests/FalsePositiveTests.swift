import XCTest
@testable import RedactApp

/// False positives are tested at least as hard as true positives.
///
/// A detector that flags every long number is not conservative-but-safe: it trains the user to
/// hit "accept all" on the review screen, and once they do that they stop reading it — which is
/// exactly when a real Aadhaar number gets through unredacted. Over-detection is a correctness
/// bug in this app, not an inconvenience.
final class FalsePositiveTests: XCTestCase {

    private let detector = PatternDetector()

    func testInvoiceCorpusProducesNoDetectionsAtAll() {
        let hits = detector.detect(in: DetectionFixtures.negativeDocument)
        XCTAssertTrue(hits.isEmpty,
                      "false positives: \(hits.map { "\($0.kind) → \($0.span.text)" })")
    }

    func testAadhaarShapedNumbersFailingVerhoeffAreNotFlagged() {
        for number in DetectionFixtures.verhoeffFailingAadhaar {
            let hits = detector.detect(in: "Reference \(number) noted.")
            XCTAssertFalse(hits.contains { $0.kind == .aadhaar },
                           "\(number) fails Verhoeff and must not be flagged as Aadhaar")
        }
    }

    func testNumbersStartingZeroOrOneAreNotAadhaar() {
        for number in DetectionFixtures.malformedAadhaar {
            let hits = detector.detect(in: "Reference \(number) noted.")
            XCTAssertFalse(hits.contains { $0.kind == .aadhaar }, "\(number)")
        }
    }

    func testCardShapedNumbersFailingLuhnAreNotFlagged() {
        for card in DetectionFixtures.luhnInvalidCards {
            let hits = detector.detect(in: "Order \(card) shipped.")
            XCTAssertFalse(hits.contains { $0.kind == .creditCard },
                           "\(card) fails Luhn and must not be flagged as a card")
        }
    }

    func testGSTINWithABadCheckCharacterIsNotFlagged() {
        for gstin in DetectionFixtures.invalidGSTIN {
            let hits = detector.detect(in: "GST \(gstin) applies.")
            XCTAssertFalse(hits.contains { $0.kind == .gstin }, "\(gstin)")
        }
    }

    func testMisshapenPANIsNotFlagged() {
        for pan in DetectionFixtures.invalidPAN {
            let hits = detector.detect(in: "Reference \(pan) noted.")
            XCTAssertFalse(hits.contains { $0.kind == .pan }, "\(pan)")
        }
    }

    func testMisshapenIFSCIsNotFlagged() {
        for ifsc in DetectionFixtures.invalidIFSC {
            let hits = detector.detect(in: "Branch \(ifsc) listed.")
            XCTAssertFalse(hits.contains { $0.kind == .ifsc }, "\(ifsc)")
        }
    }

    /// An unlabelled date is an invoice date far more often than a birth date.
    func testUnlabelledDatesAreNotBirthDates() {
        for text in ["Invoice Date: 2024-01-15", "Due 15/02/2024", "Shipped 01.03.2024"] {
            let hits = detector.detect(in: text)
            XCTAssertFalse(hits.contains { $0.kind == .dateOfBirth }, "\(text)")
        }
    }

    /// Order and tracking identifiers are the single biggest source of phone false positives.
    func testOrderIdentifiersAreNotPhoneNumbers() {
        for text in ["Tracking: ORD-8901234567", "Ticket REF-9876543210", "SKU8765432109"] {
            let hits = detector.detect(in: text)
            XCTAssertFalse(hits.contains { $0.kind == .phone }, "\(text)")
        }
    }

    /// Currency amounts and quantities must survive a scan untouched.
    func testAmountsAndCodesAreNotFlagged() {
        for text in ["Subtotal 59988.00", "HSN Code 998314", "PIN Code 600001",
                     "12 units at 4,999.00"] {
            XCTAssertTrue(detector.detect(in: text).isEmpty, "\(text)")
        }
    }

    /// The heuristic classifier layers NER on top; the structured layer must stay just as
    /// clean once it does, because NER runs on the same text.
    func testClassifierFindsNoStructuredIdentifiersInTheNegativeCorpus() async throws {
        let classifier = HeuristicClassifier()
        let hits = try await classifier.classify(text: DetectionFixtures.negativeDocument)
        let structured: Set<PIIKind> = [.aadhaar, .pan, .gstin, .ifsc, .creditCard, .email,
                                        .phone, .dateOfBirth]
        let offenders = hits.filter { structured.contains($0.kind) }
        XCTAssertTrue(offenders.isEmpty,
                      "false positives: \(offenders.map { "\($0.kind) → \($0.span.text)" })")
    }
}
