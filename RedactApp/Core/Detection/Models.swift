import CoreGraphics
import Foundation

// MARK: - PIIKind

/// A category of personal information Redact knows how to find.
///
/// Cases are ordered loosely by how structurally certain they are: the ID formats
/// carry checksums and can be asserted, whereas names and addresses are inferred.
public enum PIIKind: Hashable, Sendable, Codable {
    case personName
    case organisation
    case place
    case email
    case phone
    case pan
    case aadhaar
    case ifsc
    case gstin
    case creditCard
    case dateOfBirth
    case address
    /// A user-defined rule (Pro). The associated value is the rule's own name.
    case custom(String)

    /// Human-readable name for UI. Localised; the UI layer never builds these itself.
    public var displayName: String {
        switch self {
        case .personName:  return String(localized: "Name", comment: "PII category: a person's name")
        case .organisation: return String(localized: "Organisation", comment: "PII category: a company or institution")
        case .place:       return String(localized: "Place", comment: "PII category: a location or place name")
        case .email:       return String(localized: "Email", comment: "PII category: an email address")
        case .phone:       return String(localized: "Phone", comment: "PII category: a phone number")
        case .pan:         return String(localized: "PAN", comment: "PII category: Indian Permanent Account Number")
        case .aadhaar:     return String(localized: "Aadhaar", comment: "PII category: Indian Aadhaar number")
        case .ifsc:        return String(localized: "IFSC Code", comment: "PII category: Indian bank branch code")
        case .gstin:       return String(localized: "GSTIN", comment: "PII category: Indian GST identification number")
        case .creditCard:  return String(localized: "Card Number", comment: "PII category: a payment card number")
        case .dateOfBirth: return String(localized: "Date of Birth", comment: "PII category: a birth date")
        case .address:     return String(localized: "Address", comment: "PII category: a postal address")
        case .custom(let name): return name
        }
    }

    /// SF Symbol for the UI layer. Every case resolves to a symbol available on iOS 17.
    public var symbolName: String {
        switch self {
        case .personName:  return "person.fill"
        case .organisation: return "building.2.fill"
        case .place:       return "mappin.and.ellipse"
        case .email:       return "envelope.fill"
        case .phone:       return "phone.fill"
        case .pan:         return "person.text.rectangle.fill"
        case .aadhaar:     return "person.crop.rectangle.fill"
        case .ifsc:        return "building.columns.fill"
        case .gstin:       return "doc.text.fill"
        case .creditCard:  return "creditcard.fill"
        case .dateOfBirth: return "calendar"
        case .address:     return "house.fill"
        case .custom:      return "wand.and.stars"
        }
    }

    /// Whether a match of this kind was proven by a checksum rather than inferred.
    ///
    /// Used to break ties when two detectors claim overlapping text: a Verhoeff-valid
    /// Aadhaar beats a phone-shaped guess over the same digits.
    public var isChecksumVerified: Bool {
        switch self {
        case .aadhaar, .gstin, .creditCard: return true
        default: return false
        }
    }
}

// MARK: - TextSpan

/// A run of recognised text together with where it sits in the source.
///
/// ## Coordinate space — read this before using `boundingBox`
///
/// `boundingBox` is in **Vision's normalised coordinate space**: values run 0...1 and the
/// **origin is bottom-left**, with `y` increasing *upwards*. UIKit, Core Graphics contexts
/// created by `UIGraphicsImageRenderer`, and SwiftUI all use a **top-left** origin with `y`
/// increasing *downwards*.
///
/// Drawing a Vision rect directly into a UIKit context puts the redaction bar over the wrong
/// line of the page — the single most common bug in this class of app, and in our case a
/// correctness failure, not a cosmetic one. Convert deliberately with ``rect(in:)`` (top-left,
/// pixel coordinates) or ``topLeftOriginBoundingBox``. Never hand-roll the flip at a call site.
public struct TextSpan: Hashable, Sendable, Codable {
    /// The recognised text exactly as it appeared.
    public let text: String

    /// Offsets of ``text`` within the document string it was extracted from.
    ///
    /// These are **UTF-16 code-unit offsets**, matching `NSRange` and therefore matching what
    /// `NSRegularExpression`, `NLTagger`, and `NSAttributedString` all speak. Use ``nsRange``
    /// or ``stringRange(in:)`` rather than indexing a `String` with these integers directly.
    public let utf16Range: Range<Int>

    /// Vision-space bounding box: normalised 0...1, **bottom-left origin**.
    ///
    /// `.zero` means "no geometry" — a span that came from plain text rather than from OCR.
    public let boundingBox: CGRect

    public init(text: String, utf16Range: Range<Int>, boundingBox: CGRect = .zero) {
        self.text = text
        self.utf16Range = utf16Range
        self.boundingBox = boundingBox
    }

    public init(text: String, nsRange: NSRange, boundingBox: CGRect = .zero) {
        self.init(text: text,
                  utf16Range: nsRange.location ..< (nsRange.location + nsRange.length),
                  boundingBox: boundingBox)
    }

    public var nsRange: NSRange {
        NSRange(location: utf16Range.lowerBound, length: utf16Range.count)
    }

    /// Resolves this span's offsets against `source`, or `nil` if they do not fit it.
    public func stringRange(in source: String) -> Range<String.Index>? {
        Range(nsRange, in: source)
    }

    /// True when this span carries real OCR geometry and can therefore be redacted visually.
    public var hasGeometry: Bool { boundingBox != .zero }

    /// The same box with a **top-left** origin, still normalised 0...1.
    public var topLeftOriginBoundingBox: CGRect {
        CGRect(x: boundingBox.minX,
               y: 1.0 - boundingBox.maxY,
               width: boundingBox.width,
               height: boundingBox.height)
    }

    /// The box in pixel coordinates for a canvas of `size`, with a **top-left** origin —
    /// i.e. ready to hand to `UIGraphicsImageRenderer` or SwiftUI without further flipping.
    public func rect(in size: CGSize) -> CGRect {
        let flipped = topLeftOriginBoundingBox
        return CGRect(x: flipped.minX * size.width,
                      y: flipped.minY * size.height,
                      width: flipped.width * size.width,
                      height: flipped.height * size.height)
    }
}

// MARK: - DetectedPII

/// A span the engine believes is personal information, and how sure it is.
public struct DetectedPII: Hashable, Sendable, Codable, Identifiable {
    public let span: TextSpan
    public let kind: PIIKind
    /// Confidence in 0...1. Clamped on init — callers cannot smuggle a 1.4 through.
    public let confidence: Double

    public var id: String { "\(kind)-\(span.utf16Range.lowerBound)-\(span.utf16Range.upperBound)" }

    public init(span: TextSpan, kind: PIIKind, confidence: Double) {
        self.span = span
        self.kind = kind
        self.confidence = min(max(confidence, 0), 1)
    }

    /// The recognised text, for VoiceOver labels and the review list.
    public var text: String { span.text }
}

/// DEC-003 names the classifier's output `ClassifiedSpan`. That is exactly ``DetectedPII``;
/// the alias keeps the decision record and the code speaking the same word.
public typealias ClassifiedSpan = DetectedPII

// MARK: - Overlap resolution

extension DetectedPII {
    /// Collapses competing detections over the same text into one result per region.
    ///
    /// Two detectors legitimately fire on the same characters — a GSTIN contains a PAN, a
    /// 12-digit Aadhaar looks like a long phone number. Redacting both is harmless visually
    /// but produces a duplicated, contradictory review list, so we pick a winner:
    /// checksum-proven kinds first, then the longer match, then the higher confidence.
    public static func resolvingOverlaps(_ detections: [DetectedPII]) -> [DetectedPII] {
        let ranked = detections.sorted { lhs, rhs in
            if lhs.kind.isChecksumVerified != rhs.kind.isChecksumVerified {
                return lhs.kind.isChecksumVerified
            }
            if lhs.span.utf16Range.count != rhs.span.utf16Range.count {
                return lhs.span.utf16Range.count > rhs.span.utf16Range.count
            }
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            return lhs.span.utf16Range.lowerBound < rhs.span.utf16Range.lowerBound
        }

        var kept: [DetectedPII] = []
        for candidate in ranked {
            let clashes = kept.contains { $0.span.utf16Range.overlaps(candidate.span.utf16Range) }
            if !clashes { kept.append(candidate) }
        }
        return kept.sorted { $0.span.utf16Range.lowerBound < $1.span.utf16Range.lowerBound }
    }
}
