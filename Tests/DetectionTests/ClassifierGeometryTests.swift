import CoreGraphics
import XCTest
@testable import RedactApp

/// Offsets and coordinate spaces. Both are silent failure modes: a wrong offset highlights the
/// wrong word in the editor, and a wrong flip draws the bar over the wrong line — leaving the
/// personal information visible while the user believes it is gone.
final class ClassifierGeometryTests: XCTestCase {

    // MARK: - Vision coordinate space

    /// Vision's origin is bottom-left; UIKit's is top-left. This is the conversion every
    /// drawing path depends on, so it is pinned here rather than trusted.
    func testBoundingBoxFlipsFromVisionToTopLeftOrigin() {
        // A box on the top quarter of the page in Vision space: y from 0.8 to 0.9.
        let span = TextSpan(text: "line", utf16Range: 0 ..< 4,
                            boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.1))

        let flipped = span.topLeftOriginBoundingBox
        XCTAssertEqual(flipped.minY, 0.1, accuracy: 0.0001,
                       "a box near the top of the page must land near the top in UIKit space")
        XCTAssertEqual(flipped.minX, 0.1, accuracy: 0.0001)
        XCTAssertEqual(flipped.height, 0.1, accuracy: 0.0001)
    }

    func testRectInSizeScalesAndFlips() {
        let span = TextSpan(text: "line", utf16Range: 0 ..< 4,
                            boundingBox: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25))
        let rect = span.rect(in: CGSize(width: 400, height: 800))

        XCTAssertEqual(rect.minX, 100, accuracy: 0.001)
        XCTAssertEqual(rect.width, 200, accuracy: 0.001)
        XCTAssertEqual(rect.height, 200, accuracy: 0.001)
        // Vision y 0.5...0.75 → top-left y 0.25 → 200pt down a 800pt page.
        XCTAssertEqual(rect.minY, 200, accuracy: 0.001)
    }

    func testSpansWithoutGeometryAreIdentifiable() {
        XCTAssertFalse(TextSpan(text: "x", utf16Range: 0 ..< 1).hasGeometry)
        XCTAssertTrue(
            TextSpan(text: "x", utf16Range: 0 ..< 1,
                     boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1)).hasGeometry
        )
    }

    // MARK: - Sub-box interpolation

    func testSubBoxIsContainedByItsParent() {
        let parent = CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.05)
        let sub = HeuristicClassifier.subBox(of: parent, localRange: 4 ..< 12, unitCount: 20)

        XCTAssertTrue(parent.contains(sub), "a sub-box must never escape its line box")
        XCTAssertEqual(sub.minX, 0.1 + 0.8 * 0.2, accuracy: 0.0001)
        XCTAssertEqual(sub.width, 0.8 * 0.4, accuracy: 0.0001)
        XCTAssertEqual(sub.minY, parent.minY, accuracy: 0.0001)
        XCTAssertEqual(sub.height, parent.height, accuracy: 0.0001)
    }

    func testSubBoxClampsOutOfRangeOffsets() {
        let parent = CGRect(x: 0, y: 0, width: 1, height: 0.1)
        let sub = HeuristicClassifier.subBox(of: parent, localRange: 0 ..< 999, unitCount: 10)
        XCTAssertTrue(parent.contains(sub))
    }

    func testSubBoxOfAGeometrylessParentStaysGeometryless() {
        XCTAssertEqual(HeuristicClassifier.subBox(of: .zero, localRange: 0 ..< 2, unitCount: 4), .zero)
        XCTAssertEqual(
            HeuristicClassifier.subBox(of: CGRect(x: 0, y: 0, width: 1, height: 1),
                                       localRange: 0 ..< 2, unitCount: 0),
            .zero
        )
    }

    // MARK: - Offsets across OCR lines

    /// OCR gives one span per line. Detections inside line three must report offsets into the
    /// whole document, not into that line.
    func testDetectionOffsetsAreDocumentRelativeAcrossMultipleLines() async throws {
        let lines = ["KYC FORM", "Aadhaar 2345 6789 0124", "PAN ABCDE1234F"]
        let document = lines.joined(separator: "\n")

        var spans: [TextSpan] = []
        var offset = 0
        for (index, line) in lines.enumerated() {
            let length = (line as NSString).length
            spans.append(
                TextSpan(text: line, utf16Range: offset ..< (offset + length),
                         boundingBox: CGRect(x: 0.1, y: 0.9 - 0.1 * CGFloat(index),
                                             width: 0.8, height: 0.05))
            )
            offset += length + 1  // the newline the join inserted
        }

        let hits = try await HeuristicClassifier().classify(spans)
        let source = document as NSString

        let identifiers = hits.filter { $0.kind == .aadhaar || $0.kind == .pan }
        XCTAssertEqual(identifiers.count, 2)
        for hit in identifiers {
            XCTAssertEqual(source.substring(with: hit.span.nsRange), hit.span.text,
                           "\(hit.kind) offsets do not resolve against the document")
            XCTAssertTrue(hit.span.hasGeometry, "\(hit.kind) lost its bounding box")
        }
    }

    // MARK: - Classifier contract

    func testConfidenceIsClampedToTheUnitInterval() {
        let span = TextSpan(text: "x", utf16Range: 0 ..< 1)
        XCTAssertEqual(DetectedPII(span: span, kind: .personName, confidence: 4.2).confidence, 1)
        XCTAssertEqual(DetectedPII(span: span, kind: .personName, confidence: -3).confidence, 0)
    }

    func testChecksummedKindsOutrankInferredOnesForTheSameText() {
        let span = TextSpan(text: "2345 6789 0124", utf16Range: 0 ..< 14)
        let resolved = DetectedPII.resolvingOverlaps([
            DetectedPII(span: span, kind: .phone, confidence: 0.85),
            DetectedPII(span: span, kind: .aadhaar, confidence: 0.6),
        ])
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.kind, .aadhaar,
                       "a checksum-proven kind must beat a higher-confidence guess")
    }

    func testHeuristicClassifierFindsIdentifiersInPlainText() async throws {
        let hits = try await HeuristicClassifier().classify(text: DetectionFixtures.mixedDocument)
        let kinds = Set(hits.map(\.kind))
        for expected: PIIKind in [.aadhaar, .pan, .gstin, .ifsc, .creditCard, .email, .phone,
                                  .dateOfBirth] {
            XCTAssertTrue(kinds.contains(expected), "missing \(expected)")
        }
    }

    /// DEC-003 requires the iOS 17 path to remain fully functional and exercisable.
    func testForcedHeuristicPathIsAvailableOnEveryOS() async throws {
        let classifier = ClassifierFactory.makeHeuristic()
        let hits = try await classifier.classify(text: "PAN: ABCDE1234F")
        XCTAssertEqual(hits.first?.kind, .pan)
    }

    func testFactoryProducesAWorkingClassifier() async throws {
        let hits = try await ClassifierFactory.make().classify(text: "PAN: ABCDE1234F")
        XCTAssertEqual(hits.first(where: { $0.kind == .pan })?.span.text, "ABCDE1234F")
    }

    // MARK: - UI contract

    /// The UI layer reads these off every kind; a missing symbol renders as a blank box.
    func testEveryKindHasADisplayNameAndSymbol() {
        let kinds: [PIIKind] = [.personName, .organisation, .place, .email, .phone, .pan,
                                .aadhaar, .ifsc, .gstin, .creditCard, .dateOfBirth, .address,
                                .custom("Employee ID")]
        for kind in kinds {
            XCTAssertFalse(kind.displayName.isEmpty, "\(kind) has no display name")
            XCTAssertFalse(kind.symbolName.isEmpty, "\(kind) has no SF Symbol")
        }
        XCTAssertEqual(PIIKind.custom("Employee ID").displayName, "Employee ID")
    }
}
