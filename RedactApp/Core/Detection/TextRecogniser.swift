import CoreGraphics
import Foundation
import ImageIO
import Vision

/// The result of an OCR pass: the reconstructed document text and the spans it came from.
public struct RecognisedText: Sendable, Equatable {
    /// Every recognised line joined by newlines, in reading order.
    ///
    /// Spans index into *this* string, so downstream detection and the editor agree on offsets.
    public let text: String

    /// One span per recognised line, each carrying a Vision-space bounding box
    /// (normalised 0...1, **bottom-left origin** — see ``TextSpan``).
    public let spans: [TextSpan]

    public init(text: String, spans: [TextSpan]) {
        self.text = text
        self.spans = spans
    }

    public var isEmpty: Bool { spans.isEmpty }
}

/// On-device text recognition. Vision only — no network, per CLAUDE.md rule 1 and DEC-004.
///
/// Takes `Data` rather than `UIImage` or `CGImage` deliberately: `Data` is `Sendable`, so the
/// whole pipeline crosses concurrency domains without an `@unchecked` escape, and the caller
/// keeps its image types in the UI layer where they belong.
public struct TextRecogniser: Sendable {

    public enum Accuracy: Sendable {
        /// Slower, materially better on small print — the right default for documents where a
        /// missed line means unredacted personal information.
        case accurate
        /// For live camera preview hints, where latency matters more than a perfect read.
        case fast

        var visionLevel: VNRequestTextRecognitionLevel {
            switch self {
            case .accurate: return .accurate
            case .fast:     return .fast
            }
        }
    }

    private let accuracy: Accuracy
    private let languages: [String]
    private let usesLanguageCorrection: Bool

    public init(
        accuracy: Accuracy = .accurate,
        languages: [String] = ["en-US"],
        usesLanguageCorrection: Bool = false
    ) {
        self.accuracy = accuracy
        self.languages = languages
        // Off by default: language correction "fixes" identifiers into words —
        // it will happily turn a PAN into something spellable and defeat the checksum layer.
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    /// Recognises text in encoded image data.
    ///
    /// Runs on a detached task so a `@MainActor` caller never blocks the UI on Vision, and
    /// returns only `Sendable` values (CLAUDE.md rule 5).
    public func recognise(
        imageData: Data,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> RecognisedText {
        let accuracy = self.accuracy
        let languages = self.languages
        let correction = self.usesLanguageCorrection

        return try await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(data: imageData, orientation: orientation, options: [:])
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = accuracy.visionLevel
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = correction

            do {
                try handler.perform([request])
            } catch {
                throw DetectionError.recognitionFailed(error.localizedDescription)
            }

            guard let observations = request.results else {
                return RecognisedText(text: "", spans: [])
            }
            return Self.assemble(observations)
        }.value
    }

    /// Builds the document string and its spans from Vision observations.
    ///
    /// Exposed at `internal` visibility so the detection tests can exercise the offset
    /// arithmetic without needing a real image.
    static func assemble(_ observations: [VNRecognizedTextObservation]) -> RecognisedText {
        var lines: [(String, CGRect)] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let line = candidate.string
            guard !line.isEmpty else { continue }
            lines.append((line, observation.boundingBox))
        }

        // Reading order: top of the page first. Vision's y grows upward, so descending y is
        // descending down the page — inverting this is the classic bottom-left-origin bug.
        lines.sort { lhs, rhs in
            if abs(lhs.1.midY - rhs.1.midY) > 0.01 { return lhs.1.midY > rhs.1.midY }
            return lhs.1.minX < rhs.1.minX
        }

        var text = ""
        var spans: [TextSpan] = []
        var offset = 0
        for (index, entry) in lines.enumerated() {
            if index > 0 {
                text += "\n"
                offset += 1
            }
            let length = (entry.0 as NSString).length
            spans.append(
                TextSpan(text: entry.0, utf16Range: offset ..< (offset + length), boundingBox: entry.1)
            )
            text += entry.0
            offset += length
        }

        return RecognisedText(text: text, spans: spans)
    }
}
