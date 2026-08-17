import CoreGraphics
import Foundation

// MARK: - Protocol

/// Turns recognised text into classified personal information.
///
/// One protocol, two implementations — the iOS 17 strategy and the iOS 26 strategy — chosen
/// by ``ClassifierFactory``. See `DEC-003-ios-target`. The UI never branches on OS version;
/// only detection *quality* differs, never the feature set.
public protocol PIIClassifier: Sendable {
    func classify(_ candidates: [TextSpan]) async throws -> [ClassifiedSpan]
}

public enum DetectionError: Error, Sendable, Equatable {
    /// The supplied image data could not be decoded for recognition.
    case unreadableImage
    /// Vision returned an error while recognising text.
    case recognitionFailed(String)
}

// MARK: - Convenience

extension PIIClassifier {
    /// Classifies a plain string with no OCR geometry — used for pasted text and for tests.
    ///
    /// Resulting spans have `.zero` bounding boxes, so they can be listed and counted but not
    /// drawn over an image. ``TextSpan/hasGeometry`` distinguishes the two cases.
    public func classify(text: String) async throws -> [ClassifiedSpan] {
        let whole = TextSpan(text: text, utf16Range: 0 ..< (text as NSString).length)
        return try await classify([whole])
    }
}

// MARK: - Heuristic (iOS 17+)

/// The always-available classifier: checksum-backed regex plus `NLTagger` NER.
///
/// This is not a fallback in the apologetic sense. For the structured identifiers that matter
/// most on Indian documents — Aadhaar, PAN, GSTIN, IFSC, cards — it is *more* reliable than a
/// language model, because a checksum either passes or it does not.
public struct HeuristicClassifier: PIIClassifier {
    private let patterns: PatternDetector
    private let names: NameDetector

    public init(patterns: PatternDetector = PatternDetector(), names: NameDetector = NameDetector()) {
        self.patterns = patterns
        self.names = names
    }

    public func classify(_ candidates: [TextSpan]) async throws -> [ClassifiedSpan] {
        var results: [ClassifiedSpan] = []

        for candidate in candidates {
            let box = candidate.boundingBox
            let unitCount = (candidate.text as NSString).length
            let project: (Range<Int>) -> CGRect = { local in
                Self.subBox(of: box, localRange: local, unitCount: unitCount)
            }

            let local = patterns.detect(in: candidate.text, boundingBoxProvider: project)
                + names.detect(in: candidate.text, boundingBoxProvider: project)

            // Shift span offsets from candidate-local back into document coordinates so the
            // editor can highlight the right characters of the whole document.
            for detection in local {
                let shifted = TextSpan(
                    text: detection.span.text,
                    utf16Range: (detection.span.utf16Range.lowerBound + candidate.utf16Range.lowerBound)
                        ..< (detection.span.utf16Range.upperBound + candidate.utf16Range.lowerBound),
                    boundingBox: detection.span.boundingBox
                )
                results.append(
                    DetectedPII(span: shifted, kind: detection.kind, confidence: detection.confidence)
                )
            }
        }

        return DetectedPII.resolvingOverlaps(results)
    }

    /// Interpolates a sub-region of an OCR bounding box by character position.
    ///
    /// Vision returns one box per recognised line, not per character. Splitting the line's
    /// width proportionally is an approximation — proportional spacing means it is not exact —
    /// but it is stable, monotonic, and always contained by the parent box. The redaction
    /// layer is responsible for the safety margin it adds on top; this function must never
    /// return a box *larger* than its parent, or a bar could be drawn over the wrong line.
    static func subBox(of parent: CGRect, localRange: Range<Int>, unitCount: Int) -> CGRect {
        guard parent != .zero, unitCount > 0 else { return .zero }
        let start = min(max(localRange.lowerBound, 0), unitCount)
        let end = min(max(localRange.upperBound, start), unitCount)
        let fractionStart = CGFloat(start) / CGFloat(unitCount)
        let fractionWidth = CGFloat(end - start) / CGFloat(unitCount)
        return CGRect(
            x: parent.minX + parent.width * fractionStart,
            y: parent.minY,
            width: parent.width * fractionWidth,
            height: parent.height
        )
    }
}

// MARK: - Foundation Models (iOS 26+)

/// The iOS 26 classifier slot.
///
/// **Status: delegating to ``HeuristicClassifier``.**
///
/// DEC-003 reserves this path for Apple's on-device `FoundationModels` framework, to reason
/// about spans the heuristics cannot — whether "Salem" is a city or a surname, whether a
/// number is an account or an invoice total. That reasoning is not implemented here.
///
/// The API surface of `FoundationModels` could not be confirmed from documentation available
/// while this file was written, and a plausible-looking invented API that fails to compile
/// would be far worse than an honest gap: it would break the iOS 26 build for every other
/// agent on the project. So this type conforms to the protocol, is selected on iOS 26, and
/// currently produces exactly the heuristic result — correct, just not yet smarter.
///
/// Because the two paths return the same values today, the iOS 17 fallback is exercised on
/// every device, which is the property DEC-003 asks the verifier to check.
///
/// See `docs/memory/gotchas/foundation-models-api-unconfirmed.md` for what must be confirmed
/// before the reasoning step is added.
@available(iOS 26, *)
public struct FoundationModelClassifier: PIIClassifier {
    private let heuristic: HeuristicClassifier

    public init(heuristic: HeuristicClassifier = HeuristicClassifier()) {
        self.heuristic = heuristic
    }

    public func classify(_ candidates: [TextSpan]) async throws -> [ClassifiedSpan] {
        try await heuristic.classify(candidates)
    }
}

// MARK: - Factory

/// Chooses the best classifier the running OS supports. See DEC-003.
public enum ClassifierFactory {
    public static func make() -> any PIIClassifier {
        if #available(iOS 26, *) {
            return FoundationModelClassifier()
        }
        return HeuristicClassifier()
    }

    /// Forces the iOS 17 path regardless of OS.
    ///
    /// DEC-003 requires the verifier to run the app with the iOS 26 path off: a fallback that
    /// is never exercised is a fallback that does not work.
    public static func makeHeuristic() -> any PIIClassifier {
        HeuristicClassifier()
    }
}
