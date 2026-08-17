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
    private let labels: LabelledFieldDetector

    public init(
        patterns: PatternDetector = PatternDetector(),
        names: NameDetector = NameDetector(),
        labels: LabelledFieldDetector = LabelledFieldDetector()
    ) {
        self.patterns = patterns
        self.names = names
        self.labels = labels
    }

    public func classify(_ candidates: [TextSpan]) async throws -> [ClassifiedSpan] {
        var results: [ClassifiedSpan] = labelledNamesAcrossLines(candidates)

        for candidate in candidates {
            let box = candidate.boundingBox
            let unitCount = (candidate.text as NSString).length
            // Prefer geometry Vision actually measured for these characters. Interpolating the
            // line box by character count only holds for a monospaced face; on the proportional
            // type every real document uses it slides the bar off the words it is meant to
            // destroy. The interpolation stays as the fallback for spans with no measurements.
            let project: (Range<Int>) -> CGRect = { local in
                candidate.measuredBox(forLocalRange: local)
                    ?? Self.subBox(of: box, localRange: local, unitCount: unitCount)
            }

            let local = patterns.detect(in: candidate.text, boundingBoxProvider: project)
                + names.detect(in: candidate.text, boundingBoxProvider: project)
                + labels.detect(in: candidate.text, boundingBoxProvider: project)

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

    /// Claims the line *after* a bare field label as that field's value.
    ///
    /// OCR reads a two-column form as a stack: the sample payslip yields `Employee` and
    /// `Ananya Mehra` as separate lines, so no single-line detector can ever see the pair. Looking
    /// one line ahead is what lets the label do its work. Spans here are already in document
    /// coordinates, because a candidate's `utf16Range` is document-relative to begin with.
    private func labelledNamesAcrossLines(_ candidates: [TextSpan]) -> [ClassifiedSpan] {
        var found: [ClassifiedSpan] = []
        for (index, candidate) in candidates.enumerated() {
            guard LabelledFieldDetector.isNameLabel(candidate.text) else { continue }
            guard index + 1 < candidates.count else { continue }

            let value = candidates[index + 1]
            guard LabelledFieldDetector.looksLikeAPersonName(value.text) else { continue }

            let local = 0 ..< (value.text as NSString).length
            let box = value.measuredBox(forLocalRange: local) ?? value.boundingBox
            found.append(
                DetectedPII(
                    span: TextSpan(text: value.text, utf16Range: value.utf16Range, boundingBox: box),
                    kind: .personName,
                    confidence: 0.8
                )
            )
        }
        return found
    }

    /// Interpolates a sub-region of an OCR bounding box by character position.
    ///
    /// **This is the fallback, not the primary path.** Real geometry comes from
    /// ``TextSpan/measuredBox(forLocalRange:)``, which reports what Vision measured for those
    /// exact characters. Splitting the line box proportionally is only correct for a monospaced
    /// face; on proportional type it drifts, and a drifted bar means personal information stays
    /// on the page (see `docs/memory/gotchas/vision-per-character-geometry.md`). It is kept for
    /// spans that carry no per-character measurements at all, where a slightly wrong box is
    /// still better than none. It is stable, monotonic, and never larger than its parent.
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
