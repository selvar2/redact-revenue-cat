import CoreGraphics
import Foundation
import PDFKit
import UIKit

// MARK: - What this file is for
//
// `RedactionEngine.redactedPDFData` rasterises every page that carries a redaction and inserts
// every other page **verbatim** — content stream, annotations and all. That pass-through is what
// keeps untouched pages text-searchable, and it is also a hole: if some other tool "redacted" the
// source by drawing a black `PDFAnnotation` square over a page we never touch, that square ships
// intact. The recipient deletes it in Preview and reads what is underneath, believing our app made
// the file safe.
//
// See docs/memory/gotchas/pdf-passthrough-pages-keep-annotations.md. The product decision taken for
// F09 is **detect and offer**: find these marks before export, tell the user in plain language what
// is on the page, and let them choose. We never silently flatten (it would destroy selectable text
// on pages they never touched) and never silently strip (it would discard real signatures and
// comments).
//
// This file is the detection half. `InsecureMarkupSheet` is the offer, and `ExportPipeline` carries
// out whichever choice was made.

/// Scans a PDF for markup that may be concealing text rather than annotating it.
///
/// Everything here is `nonisolated` and takes/returns `Sendable` values (`Data` in, a value-type
/// report out). `PDFDocument` never crosses an isolation boundary — it is created, used and
/// destroyed inside a single function body, exactly as `RedactionEngine` does it.
public enum AnnotationAudit {

    // MARK: - Mark types

    /// The kinds of annotation that can hide text under an opaque fill.
    ///
    /// Deliberately not "every annotation subtype". A link, a form field or a stamp does not conceal
    /// running text, and a warning that fires on those trains users to dismiss the warning — which
    /// is worse than no warning at all, because the one time it matters they will dismiss that too.
    public enum MarkType: String, Sendable, Hashable, CaseIterable {
        /// A filled rectangle. The classic fake redaction.
        case box
        /// A real `/Redact` annotation that was never applied — the content is still there.
        case pendingRedactionMark
        /// Freehand drawing. A signature, or a scribble over a name.
        case drawing
        /// A highlight. Normally translucent and harmless; opaque ones are used to black out.
        case highlight
        /// A text box drawn on top of the page, often with an opaque background.
        case textBox
        /// A sticky note that is displayed rather than collapsed.
        case note

        init?(subtype: PDFAnnotationSubtype) {
            // PDFKit ships no `.redact` constant, so the /Redact subtype is matched by raw value.
            if subtype.rawValue.hasSuffix("Redact") {
                self = .pendingRedactionMark
                return
            }
            switch subtype {
            case .square:   self = .box
            case .ink:      self = .drawing
            case .highlight: self = .highlight
            case .freeText: self = .textBox
            case .popup:    self = .note
            default:        return nil
            }
        }

        /// Plain-language name for the sheet. No jargon: a user does not know what an "annotation"
        /// or a "freeText" is, and does not need to.
        public var plainName: String {
            switch self {
            case .box:
                return String(localized: "a black box", comment: "Plain-language name for a filled rectangle drawn on a PDF page")
            case .pendingRedactionMark:
                return String(localized: "a marked-out area", comment: "Plain-language name for an unapplied redaction mark on a PDF page")
            case .drawing:
                return String(localized: "a drawing", comment: "Plain-language name for freehand ink drawn on a PDF page")
            case .highlight:
                return String(localized: "a solid highlight", comment: "Plain-language name for an opaque highlight on a PDF page")
            case .textBox:
                return String(localized: "a text box", comment: "Plain-language name for a text box placed on a PDF page")
            case .note:
                return String(localized: "a note", comment: "Plain-language name for a sticky note shown on a PDF page")
            }
        }

        /// How opaque the fill must be before this mark can hide anything.
        ///
        /// A highlight is designed to be seen through — the standard yellow one multiplies, and
        /// text under it stays perfectly readable. Only a near-solid one is doing a black bar's
        /// job, so it needs a much higher bar than a square whose whole purpose is to be filled.
        var opacityThreshold: CGFloat {
            switch self {
            case .highlight: return 0.9
            case .box, .pendingRedactionMark, .drawing, .textBox, .note: return 0.6
            }
        }
    }

    // MARK: - Findings

    /// One page that carries markup with extractable text underneath it.
    ///
    /// It deliberately records **no sample of the hidden text**. Copying "the words we found under
    /// the box" into a report — and then into a warning sheet — would re-expose the exact content
    /// the user is trying to protect (CLAUDE.md rule 2). The character count is enough to say "there
    /// is real text under here" without repeating it.
    public struct Finding: Sendable, Hashable, Identifiable {
        /// Zero-based page index, matching `PageRedaction.pageIndex` and `SessionPage.index`.
        public let pageIndex: Int
        /// Which kinds of mark were found on this page, in the order encountered.
        public let markTypes: [MarkType]
        /// Number of characters of extractable text sitting under those marks.
        public let hiddenCharacterCount: Int
        /// The covering marks, normalised `0...1` with a **top-left** origin — ready to draw over a
        /// page thumbnail with no further flipping.
        public let markRects: [CGRect]

        public var id: Int { pageIndex }

        public init(pageIndex: Int, markTypes: [MarkType], hiddenCharacterCount: Int, markRects: [CGRect]) {
            self.pageIndex = pageIndex
            self.markTypes = markTypes
            self.hiddenCharacterCount = hiddenCharacterCount
            self.markRects = markRects
        }

        /// The dominant mark type, used when the sheet needs one noun for the page.
        public var primaryMarkType: MarkType { markTypes.first ?? .box }
    }

    /// The result of auditing a whole document.
    public struct Report: Sendable, Hashable {
        /// Pages where a mark is covering extractable text. **These are the only pages the user is
        /// warned about**, because these are the only ones where removing the mark reveals
        /// something.
        public let findings: [Finding]

        /// Pages carrying markup of a concealing *kind* that turned out to hide nothing — a
        /// signature in a blank margin, a note beside the text. Recorded so the export screen can
        /// avoid claiming the file has no markup at all, and never surfaced as a warning.
        public let benignMarkupPageIndices: [Int]

        public init(findings: [Finding], benignMarkupPageIndices: [Int]) {
            self.findings = findings
            self.benignMarkupPageIndices = benignMarkupPageIndices
        }

        public static let clean = Report(findings: [], benignMarkupPageIndices: [])

        /// True when nothing needs the user's attention.
        public var isEmpty: Bool { findings.isEmpty }

        public var flaggedPageIndices: [Int] { findings.map(\.pageIndex) }

        public func finding(forPage pageIndex: Int) -> Finding? {
            findings.first { $0.pageIndex == pageIndex }
        }
    }

    // MARK: - Audit

    /// Scans **every** page of a PDF, including pages the user is not otherwise redacting.
    ///
    /// Pages we are about to redact get rasterised anyway, so their markup is destroyed by the
    /// engine — but they are still scanned and still reported. The alternative is a report whose
    /// contents depend on what the user happened to select, which would make the warning appear and
    /// disappear as they toggled detections in the editor.
    ///
    /// - Parameter pdfData: source PDF bytes.
    /// - Returns: a report, or ``Report/clean`` for a document with no markup.
    /// - Throws: `AuditError.unreadablePDF` when the bytes are not a PDF.
    public static func audit(pdfData: Data) throws -> Report {
        guard let document = PDFDocument(data: pdfData) else { throw AuditError.unreadablePDF }

        var findings: [Finding] = []
        var benign: [Int] = []

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let box = page.bounds(for: .mediaBox)
            guard box.width > 0, box.height > 0 else { continue }

            var markTypes: [MarkType] = []
            var markRects: [CGRect] = []
            var hiddenCharacters = 0
            var sawConcealingCandidate = false

            for annotation in page.annotations {
                guard
                    let markType = annotation.type.flatMap(markType(forTypeName:)),
                    isOpaqueEnoughToConceal(annotation, markType: markType)
                else { continue }

                sawConcealingCandidate = true

                let covered = annotation.bounds.intersection(box)
                guard !covered.isNull, !covered.isEmpty else { continue }

                let hidden = extractableText(under: covered, on: page)
                guard !hidden.isEmpty else { continue }

                hiddenCharacters += hidden.count
                markTypes.append(markType)
                markRects.append(normalisedTopLeftRect(of: covered, in: box))
            }

            if !markTypes.isEmpty {
                findings.append(
                    Finding(
                        pageIndex: index,
                        markTypes: markTypes,
                        hiddenCharacterCount: hiddenCharacters,
                        markRects: markRects
                    )
                )
            } else if sawConcealingCandidate {
                benign.append(index)
            }
        }

        return Report(findings: findings, benignMarkupPageIndices: benign)
    }

    /// Maps `PDFAnnotation.type` onto a ``MarkType``.
    ///
    /// `type` is documented as the subtype name and is observed both with and without the leading
    /// solidus depending on how the annotation was constructed, so the name is normalised before
    /// it is matched rather than compared against one spelling and silently missing the other —
    /// a miss here is a warning that never fires.
    private static func markType(forTypeName name: String) -> MarkType? {
        let bare = name.hasPrefix("/") ? String(name.dropFirst()) : name
        return MarkType(subtype: PDFAnnotationSubtype(rawValue: "/" + bare))
    }

    // MARK: - Is it actually hiding something?

    /// The text a reader would recover by deleting the mark.
    ///
    /// This is the whole discriminator. A signature over a blank line and a black box over an
    /// account number are the same object to PDFKit; the only thing that separates a harmless
    /// comment from a peel-off fake redaction is whether the page still has glyphs underneath.
    /// Getting this wrong in the permissive direction is not a cosmetic bug: a warning that fires on
    /// every signed contract teaches the user to tap through it, and the one document that really is
    /// leaking gets tapped through too.
    private static func extractableText(under rect: CGRect, on page: PDFPage) -> String {
        guard let selection = page.selection(for: rect) else { return "" }
        return selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Whether the mark is solid enough to actually hide what is under it.
    ///
    /// An unfilled square is a *frame*: the text inside it is plainly visible, nobody believes it is
    /// redacted, and warning about it would be noise.
    private static func isOpaqueEnoughToConceal(_ annotation: PDFAnnotation, markType: MarkType) -> Bool {
        // A `/Redact` annotation that survived into the file means some tool marked content for
        // removal and never applied it. That is a leak regardless of how it is painted.
        if markType == .pendingRedactionMark { return true }

        // A collapsed note draws nothing over the page.
        guard annotation.shouldDisplay else { return false }

        let threshold = markType.opacityThreshold
        let candidates = [annotation.interiorColor, annotation.backgroundColor, annotation.color]
        for colour in candidates.compactMap({ $0 }) where alpha(of: colour) >= threshold {
            return true
        }
        return false
    }

    private static func alpha(of colour: UIColor) -> CGFloat {
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        if colour.getWhite(&white, alpha: &alpha) { return alpha }
        return colour.cgColor.alpha
    }

    // MARK: - Geometry

    /// Converts a rect in PDF page space (points, **bottom-left** origin) to the normalised
    /// top-left space the rest of the app draws in.
    ///
    /// The flip is not written here. It is delegated to Core's
    /// `RedactionRegion.init(visionBoundingBox:style:)`, which is one of the two functions in the
    /// whole app allowed to contain a `1 - y`. Vision boxes and PDF page rects share the same
    /// bottom-left convention once normalised, so the existing conversion is the correct one — and
    /// reusing it means a fix there fixes every caller.
    private static func normalisedTopLeftRect(of rect: CGRect, in pageBox: CGRect) -> CGRect {
        let bottomLeftNormalised = CGRect(
            x: (rect.minX - pageBox.minX) / pageBox.width,
            y: (rect.minY - pageBox.minY) / pageBox.height,
            width: rect.width / pageBox.width,
            height: rect.height / pageBox.height
        )
        return RedactionRegion(visionBoundingBox: bottomLeftNormalised).rect.clampedToUnitSquare()
    }

    // MARK: - Errors

    public enum AuditError: Error, Sendable, Equatable, LocalizedError {
        case unreadablePDF

        public var errorDescription: String? {
            switch self {
            case .unreadablePDF:
                return String(localized: "This PDF could not be checked for existing marks.",
                              comment: "Error shown when the annotation audit cannot open a PDF")
            }
        }

        public var recoverySuggestion: String? {
            String(localized: "You can still export, but Redact cannot tell you whether the file already has marks drawn on it.",
                   comment: "Recovery suggestion when the annotation audit fails")
        }
    }
}
