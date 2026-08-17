import CoreGraphics
import Foundation

/// Deterministic, checksum-backed detection of structured identifiers.
///
/// This is the half of the engine that can be *certain*. Where ``NameDetector`` infers, this
/// type proves: an Aadhaar match has passed Verhoeff, a card match has passed Luhn, a GSTIN
/// match has passed its base-36 check character. Everything it emits at high confidence is
/// something we can defend to a user who asks "why did you black that out?".
///
/// Design notes:
/// - Patterns are compiled per call rather than cached in `static let`. `NSRegularExpression`
///   is not `Sendable`, and CLAUDE.md rule 5 forbids `@unchecked Sendable` escapes. Compiling
///   a dozen small patterns costs microseconds against an OCR pass that costs hundreds of
///   milliseconds, so the safe option is also the sensible one.
/// - Identifier patterns are **case-sensitive uppercase**. PAN, GSTIN, and IFSC are printed
///   uppercase on every real document, and matching case-insensitively turns ordinary words
///   with trailing digits into false positives.
public struct PatternDetector: Sendable {

    public init() {}

    /// Finds every structured identifier in `text`.
    ///
    /// - Parameter boundingBoxProvider: maps a matched UTF-16 range back to a Vision-space
    ///   box (normalised, bottom-left origin). Supply it when `text` came from OCR; omit it
    ///   for plain text, in which case spans carry `.zero` geometry.
    public func detect(
        in text: String,
        boundingBoxProvider: ((Range<Int>) -> CGRect)? = nil
    ) -> [DetectedPII] {
        let nsText = text as NSString
        let whole = NSRange(location: 0, length: nsText.length)
        var found: [DetectedPII] = []

        for rule in Rule.all {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
                continue
            }
            regex.enumerateMatches(in: text, options: [], range: whole) { match, _, _ in
                guard let match else { return }
                // Rules that label their payload (date of birth) redact the value, not the label.
                let payloadRange = rule.capturesPayloadAtGroup.map { match.range(at: $0) } ?? match.range
                guard payloadRange.location != NSNotFound, payloadRange.length > 0 else { return }

                let matched = nsText.substring(with: payloadRange)
                guard rule.validate(matched) else { return }

                let utf16Range = payloadRange.location ..< (payloadRange.location + payloadRange.length)
                let box = boundingBoxProvider?(utf16Range) ?? .zero
                found.append(
                    DetectedPII(
                        span: TextSpan(text: matched, utf16Range: utf16Range, boundingBox: box),
                        kind: rule.kind,
                        confidence: rule.confidence
                    )
                )
            }
        }

        return DetectedPII.resolvingOverlaps(found)
    }

    // MARK: - Rules

    private struct Rule {
        let kind: PIIKind
        let pattern: String
        var options: NSRegularExpression.Options = []
        /// Capture group holding the text to redact, when it differs from the whole match.
        var capturesPayloadAtGroup: Int?
        /// Confidence before any classifier refinement. Checksummed formats sit at the top.
        let confidence: Double
        /// Second-stage validation. Regex shape is necessary but rarely sufficient.
        let validate: @Sendable (String) -> Bool

        static let all: [Rule] = [
            .gstin, .aadhaar, .creditCard, .pan, .ifsc, .email, .indianPhone,
            .internationalPhone, .dateOfBirth,
        ]

        // 2-digit state code + PAN + entity number + 'Z' + check character.
        // Checked last-character-first because the checksum is what makes this trustworthy.
        static let gstin = Rule(
            kind: .gstin,
            pattern: #"(?<![A-Z0-9])[0-3][0-9][A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z](?![A-Z0-9])"#,
            confidence: 0.99,
            validate: { candidate in
                guard let stateCode = Int(candidate.prefix(2)), (1...38).contains(stateCode) else {
                    return false
                }
                return Checksum.isGSTINChecksumValid(candidate)
            }
        )

        // 12 digits, conventionally grouped 4-4-4. Never begins with 0 or 1 (UIDAI rule),
        // and must satisfy Verhoeff — a bare 12-digit pattern flags invoice totals.
        static let aadhaar = Rule(
            kind: .aadhaar,
            // The `[ -][0-9]` lookarounds stop the pattern latching onto the middle twelve
            // digits of a grouped 16-digit card number.
            pattern: #"(?<![0-9])(?<![0-9][ -])[2-9][0-9]{3}[ -]?[0-9]{4}[ -]?[0-9]{4}(?![0-9])(?![ -][0-9])"#,
            confidence: 0.99,
            validate: { candidate in
                let digits = candidate.filter(\.isNumber)
                guard digits.count == 12 else { return false }
                return Checksum.Verhoeff.isValid(digits)
            }
        )

        // 13–19 digits with optional single space/hyphen separators, then Luhn.
        static let creditCard = Rule(
            kind: .creditCard,
            pattern: #"(?<![0-9])(?:[0-9][ -]?){12,18}[0-9](?![0-9])"#,
            confidence: 0.98,
            validate: { candidate in
                let digits = candidate.filter(\.isNumber)
                guard (13...19).contains(digits.count) else { return false }
                return Checksum.isLuhnValid(digits)
            }
        )

        // 5 letters, 4 digits, 1 letter. No checksum exists, so confidence stays below the
        // checksummed formats — the shape alone is strong but not proof.
        static let pan = Rule(
            kind: .pan,
            pattern: #"(?<![A-Z0-9])[A-Z]{5}[0-9]{4}[A-Z](?![A-Z0-9])"#,
            confidence: 0.9,
            validate: { _ in true }
        )

        // 4 letters, a literal 0, then 6 alphanumerics.
        static let ifsc = Rule(
            kind: .ifsc,
            pattern: #"(?<![A-Z0-9])[A-Z]{4}0[A-Z0-9]{6}(?![A-Z0-9])"#,
            confidence: 0.9,
            validate: { _ in true }
        )

        static let email = Rule(
            kind: .email,
            pattern: #"(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}(?![A-Za-z0-9-])"#,
            confidence: 0.97,
            validate: { $0.count <= 254 }
        )

        // Indian mobile: optional +91 or leading 0, then a 10-digit number starting 6–9,
        // optionally split 5-5 as it is conventionally printed.
        // The lookbehind excludes letters and hyphens so order IDs like ORD-8901234567
        // do not read as phone numbers.
        static let indianPhone = Rule(
            kind: .phone,
            pattern: #"(?<![0-9A-Za-z\-])(?:\+91[ -]?)?(?:0[ -]?)?[6-9][0-9]{4}[ -]?[0-9]{5}(?![0-9])"#,
            confidence: 0.85,
            validate: { _ in true }
        )

        // Any other country code, written explicitly with a +.
        static let internationalPhone = Rule(
            kind: .phone,
            pattern: #"(?<![0-9+])\+(?!91)[0-9]{1,3}[ -]?(?:[0-9][ -]?){5,13}[0-9](?![0-9])"#,
            confidence: 0.8,
            validate: { candidate in
                let digits = candidate.filter(\.isNumber)
                return (8...15).contains(digits.count)
            }
        )

        // Dates are only personal information when something says they are. An unlabelled
        // date is an invoice date far more often than a birth date, so we require the label
        // and redact the value that follows it.
        static let dateOfBirth = Rule(
            kind: .dateOfBirth,
            pattern: #"(?:D\.?O\.?B\.?|Date of Birth|Birth ?date|Born(?: on)?)\s*[:\-]?\s*([0-9]{1,2}[/\-.][0-9]{1,2}[/\-.][0-9]{2,4}|[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{1,2}[ ][A-Za-z]{3,9}[ ][0-9]{4})"#,
            options: [.caseInsensitive],
            capturesPayloadAtGroup: 1,
            confidence: 0.92,
            validate: { _ in true }
        )
    }
}
