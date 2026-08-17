import CoreGraphics
import Foundation

/// Finds personal names by the **label printed next to them**, rather than by recognising the name.
///
/// `NLTagger` is a general-purpose model trained on prose. On a form it is weak in exactly the
/// place this app cannot afford weakness: it does not tag "Ananya Mehra" on a payslip — a bare
/// two-word line with no sentence around it — while it happily tags "August" in a document title.
/// A named-entity model that has never seen a particular name has no way to know it is one.
///
/// A form tells us anyway. Documents label their fields: `Employee`, `Account Holder`,
/// `Beneficiary Name`. Whatever sits in the value position of one of those labels is a person's
/// name whether or not any model recognises it, and that is true for names from every language,
/// which a model trained largely on Western prose is not. This is the same reasoning
/// ``PatternDetector`` already uses for `Date of Birth:` — a label is evidence.
///
/// Two shapes are handled, because OCR splits a form's columns unpredictably:
/// - inline, `Employee: Ananya Mehra`, within one recognised line
/// - stacked, where `Employee` and `Ananya Mehra` are recognised as consecutive lines
public struct LabelledFieldDetector: Sendable {

    /// Labels whose value is a person's name. Matched case- and punctuation-insensitively.
    ///
    /// Deliberately narrow. `Designation` and `Employee ID` are *not* here: their values are a job
    /// title and a code, and claiming those are names would put bars over text the user then has to
    /// switch off one by one — which trains people to switch bars off, the opposite of what a
    /// redaction tool wants.
    private static let nameLabels: Set<String> = [
        "name", "full name", "employee", "employee name", "staff name",
        "account holder", "account holder name", "accountholder",
        "beneficiary", "beneficiary name", "cardholder", "cardholder name",
        "customer", "customer name", "applicant", "applicant name",
        "patient", "patient name", "candidate", "candidate name",
        "father's name", "mother's name", "spouse name", "guardian", "guardian name",
    ]

    /// Below the checksummed formats — a label is strong evidence, not proof — and above
    /// `NLTagger`'s inferred names, because a printed label is better evidence than a model's
    /// guess about the same characters.
    private static let confidence = 0.8

    public init() {}

    // MARK: - Inline: "Employee: Ananya Mehra"

    /// Detects a labelled name inside a single line of text.
    ///
    /// - Parameter boundingBoxProvider: maps a matched UTF-16 range to a Vision-space box
    ///   (normalised, bottom-left origin). Omit for plain text.
    public func detect(
        in text: String,
        boundingBoxProvider: ((Range<Int>) -> CGRect)? = nil
    ) -> [DetectedPII] {
        guard let separator = text.firstIndex(where: { $0 == ":" || $0 == "-" || $0 == "–" }) else {
            return []
        }
        let label = String(text[text.startIndex ..< separator])
        guard Self.isNameLabel(label) else { return [] }

        let valueStart = text.index(after: separator)
        guard valueStart < text.endIndex else { return [] }
        let rawValue = String(text[valueStart...])
        guard Self.looksLikeAPersonName(rawValue) else { return [] }

        // Offsets must select the value exactly — leading spaces belong to neither the label nor
        // the name, and including them would draw a bar wider than the text it destroys.
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        guard let valueRange = text.range(of: trimmed, options: .backwards) else { return [] }
        let lower = text.utf16.distance(from: text.startIndex, to: valueRange.lowerBound)
        let upper = text.utf16.distance(from: text.startIndex, to: valueRange.upperBound)
        guard lower < upper else { return [] }

        let utf16Range = lower ..< upper
        return [
            DetectedPII(
                span: TextSpan(text: trimmed,
                               utf16Range: utf16Range,
                               boundingBox: boundingBoxProvider?(utf16Range) ?? .zero),
                kind: .personName,
                confidence: Self.confidence
            )
        ]
    }

    // MARK: - Stacked: "Employee" / "Ananya Mehra" on consecutive lines

    /// Whether `line` is a bare field label whose next line is that field's value.
    public static func isNameLabel(_ line: String) -> Bool {
        let normalised = line
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t:-–—"))
            .lowercased()
        return nameLabels.contains(normalised)
    }

    /// Whether `candidate` has the shape of a printed personal name.
    ///
    /// Shape only — no vocabulary, deliberately. A name list would work for the names on it and
    /// fail for everyone else, and "everyone else" is most of the world.
    public static func looksLikeAPersonName(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 60 else { return false }

        // A digit means an identifier or a date, not a name. This is what keeps `Employee ID`'s
        // `NWA-2291` out even if someone adds that label to the set by mistake.
        guard !trimmed.contains(where: \.isNumber) else { return false }

        let words = trimmed.split(separator: " ")
        guard (1 ... 5).contains(words.count) else { return false }

        for word in words {
            guard let first = word.first, first.isUppercase || !first.isCased else { return false }
            let permitted = word.allSatisfy { $0.isLetter || $0 == "." || $0 == "'" || $0 == "-" }
            guard permitted else { return false }
        }
        return true
    }
}
