import CoreGraphics
import Foundation
import NaturalLanguage

/// Named-entity detection for people, places, and organisations.
///
/// Wraps `NLTagger` with the `.nameType` scheme. Unlike ``PatternDetector`` this layer
/// *infers* — "Salem" is a city in Tamil Nadu and a surname elsewhere — so its confidence
/// values sit deliberately below the checksummed formats, and the review screen shows these
/// spans as suggestions the user can decline.
///
/// A fresh `NLTagger` is created per call: `NLTagger` is a reference type holding mutable
/// tagging state and is not `Sendable`, so sharing one across tasks would be exactly the
/// data race CLAUDE.md rule 5 exists to prevent.
public struct NameDetector: Sendable {

    /// Below this, `NLTagger`'s guesses are noise — mostly capitalised sentence starts.
    private let minimumConfidence: Double

    public init(minimumConfidence: Double = 0.3) {
        self.minimumConfidence = minimumConfidence
    }

    /// Finds person, place, and organisation names in `text`.
    ///
    /// - Parameter boundingBoxProvider: maps a matched UTF-16 range to a Vision-space box
    ///   (normalised, bottom-left origin). Omit for plain text.
    public func detect(
        in text: String,
        boundingBoxProvider: ((Range<Int>) -> CGRect)? = nil
    ) -> [DetectedPII] {
        guard !text.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var found: [DetectedPII] = []
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

        tagger.enumerateTags(
            in: text.startIndex ..< text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            guard let tag, let kind = Self.kind(for: tag) else { return true }

            let matched = String(text[range])
            guard matched.count > 1 else { return true }

            // `NLTagger` reports a hypothesis score per tag; use it directly rather than
            // inventing a flat confidence, so the review list can sort honestly.
            let hypotheses = tagger.tagHypotheses(
                at: range.lowerBound, unit: .word, scheme: .nameType, maximumCount: 1
            )
            let score = hypotheses.0[tag.rawValue] ?? Self.defaultConfidence
            guard score >= self.minimumConfidence else { return true }

            let lower = text.utf16.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.utf16.distance(from: text.startIndex, to: range.upperBound)
            guard lower < upper else { return true }

            let utf16Range = lower ..< upper
            let box = boundingBoxProvider?(utf16Range) ?? .zero
            found.append(
                DetectedPII(
                    span: TextSpan(text: matched, utf16Range: utf16Range, boundingBox: box),
                    kind: kind,
                    // Cap below the checksummed formats: an inferred name must never
                    // outrank a proven identifier when they compete for the same text.
                    confidence: min(score, 0.75)
                )
            )
            return true
        }

        return DetectedPII.resolvingOverlaps(found)
    }

    /// `NLTagger` scores are frequently absent for confidently-tagged spans; when the tagger
    /// commits to a name but reports nothing, treat it as a moderate hit rather than dropping it.
    private static let defaultConfidence = 0.6

    private static func kind(for tag: NLTag) -> PIIKind? {
        switch tag {
        case .personalName:     return .personName
        case .placeName:        return .place
        case .organizationName: return .organisation
        default:                return nil
        }
    }
}
