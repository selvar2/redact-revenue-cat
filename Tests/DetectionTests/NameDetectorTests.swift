import CoreGraphics
import XCTest
@testable import RedactApp

/// `NLTagger` is a model, not a rule set — its exact output shifts between OS releases, so
/// asserting "it finds Priya Sharma" would make the suite fail on an OS update for no real
/// defect. These tests pin the *contract* instead: valid offsets, valid kinds, bounded
/// confidence, and no spurious structured identifiers.
final class NameDetectorTests: XCTestCase {

    private let detector = NameDetector()

    func testEveryDetectionResolvesAgainstTheSourceText() {
        let text = "Priya Sharma met Rajesh Kumar at Infosys in Bengaluru on Tuesday."
        let source = text as NSString

        for hit in detector.detect(in: text) {
            XCTAssertEqual(source.substring(with: hit.span.nsRange), hit.span.text,
                           "offsets for \(hit.kind) do not select their own text")
        }
    }

    func testOnlyNameKindsAreEmitted() {
        let allowed: Set<PIIKind> = [.personName, .place, .organisation]
        let hits = detector.detect(in: "Priya Sharma works at Infosys in Bengaluru.")
        for hit in hits {
            XCTAssertTrue(allowed.contains(hit.kind), "unexpected kind \(hit.kind)")
        }
    }

    /// An inferred name must never outrank a checksum-proven identifier when they compete,
    /// so its confidence is capped below theirs by construction.
    func testInferredConfidenceStaysBelowTheChecksummedFloor() {
        for hit in detector.detect(in: "Priya Sharma met Rajesh Kumar at Infosys in Bengaluru.") {
            XCTAssertLessThanOrEqual(hit.confidence, 0.75, "\(hit.span.text)")
            XCTAssertGreaterThan(hit.confidence, 0)
        }
    }

    func testSingleCharacterTokensAreIgnored() {
        for hit in detector.detect(in: "A B C D E F") {
            XCTAssertGreaterThan(hit.span.text.count, 1)
        }
    }

    func testEmptyAndWhitespaceInputAreHandled() {
        XCTAssertTrue(detector.detect(in: "").isEmpty)
        XCTAssertTrue(detector.detect(in: "   \n  ").isEmpty)
    }

    func testBoundingBoxProviderIsAppliedWhenSupplied() {
        let box = CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.05)
        let hits = detector.detect(in: "Priya Sharma lives in Bengaluru.") { _ in box }
        for hit in hits {
            XCTAssertEqual(hit.span.boundingBox, box)
        }
    }
}
