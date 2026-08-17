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
        var lines: [(String, CGRect, [CGRect])] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let line = candidate.string
            guard !line.isEmpty else { continue }
            lines.append((line, observation.boundingBox,
                          characterBoxes(of: candidate, within: observation.boundingBox)))
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
                TextSpan(text: entry.0,
                         utf16Range: offset ..< (offset + length),
                         boundingBox: entry.1,
                         characterBoxes: entry.2)
            )
            text += entry.0
            offset += length
        }

        return RecognisedText(text: text, spans: spans)
    }

    /// Measures every character of a recognised line, one Vision-space box per UTF-16 code unit.
    ///
    /// `VNRecognizedText.boundingBox(for:)` is the only source of truth about *where inside a line*
    /// a substring sits. Without it the classifier can only divide the line box by character count,
    /// which is wrong by a growing margin across any proportional typeface — the defect that let the
    /// sample payslip export with the employee's name uncovered. Querying once per character here,
    /// off the main actor and once per page, buys exact geometry for every detection downstream.
    ///
    /// Two classes of answer are rejected, both observed on the bundled sample:
    ///
    /// - **Whitespace is never queried.** Asked for the box of a lone space, Vision returns a quad
    ///   spanning most of the page rather than failing. Unioned into a detection's geometry that
    ///   became a bar over the entire top half of the payslip — every identifier on the sample
    ///   contains a space, so this was not an edge case.
    /// - **Anything outside the line is dropped.** A character's box that does not sit inside its
    ///   own line's box is not a measurement of that character, whatever it is.
    ///
    /// Rejected characters are recorded as `.zero`; ``TextSpan/measuredBox(forLocalRange:)``
    /// unions around them, which is correct — a space between two measured glyphs is covered by
    /// the union of its neighbours.
    static func characterBoxes(of candidate: VNRecognizedText, within lineBox: CGRect) -> [CGRect] {
        let string = candidate.string
        var boxes: [CGRect] = []
        boxes.reserveCapacity((string as NSString).length)

        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(after: index)
            let character = string[index ..< next]

            var box = CGRect.zero
            if !character.allSatisfy(\.isWhitespace),
               let measured = (try? candidate.boundingBox(for: index ..< next))?.boundingBox,
               isPlausible(measured, within: lineBox) {
                box = measured
            }

            // A Character can be several UTF-16 units; offsets downstream are UTF-16, so each
            // unit of a grapheme carries that grapheme's box.
            for _ in 0 ..< character.utf16.count {
                boxes.append(box)
            }
            index = next
        }
        return boxes
    }

    /// A character box is trusted only if it is really inside the line it came from.
    ///
    /// The tolerance exists because Vision's per-character quads sit a fraction of a percent
    /// outside the line box at ascenders and descenders; it is far tighter than the drift this
    /// whole mechanism exists to prevent.
    private static func isPlausible(_ box: CGRect, within lineBox: CGRect) -> Bool {
        guard box.width > 0, box.height > 0 else { return false }
        let slack = max(lineBox.height, 0.005)
        let permitted = lineBox.insetBy(dx: -slack, dy: -slack)
        return permitted.contains(box)
    }
}
