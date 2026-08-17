import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// The one path from "what the user decided" to "bytes on disk that are safe to send".
///
/// Shape of the work:
///
/// ```
/// @MainActor  read the session's decisions (activeRegions / pageRedactions)
/// @MainActor  check the free-tier quota — a blocked export never destroys anything
///   detached  RedactionEngine  ← the only place data is destroyed, ever
///   detached  render a thumbnail from the *redacted* output
///   detached  FileVault.write
/// @MainActor  DocumentStore.insert + audit records
/// @MainActor  UsageTracker.recordDocumentProcessed  ← only after success
/// ```
///
/// Redaction is not reimplemented here and must never be: `RedactionEngine` is the audited path,
/// it is what `IrreversibilityTests` attacks, and a second implementation would be a second thing
/// to prove correct. This type decides *what* to destroy and *where the result goes*.
public enum ExportPipeline {

    // MARK: - Tier

    /// What the current user is allowed to export.
    ///
    /// Deliberately a plain value, not an entitlement object: nothing in `Features/Export` knows
    /// what a subscription is, so Phase 3 can wire RevenueCat in without touching this file
    /// (CLAUDE.md rule 1 keeps the SDK confined, and the paywall seam lives on `AppCoordinator`).
    public enum Tier: Sendable, Hashable {
        case free
        case pro

        public var isPro: Bool { self == .pro }
    }

    // MARK: - Format

    /// Encoding of the exported file.
    public enum Format: Sendable, Hashable, CaseIterable, Identifiable {
        /// One page, as a lossless image. Available on every tier.
        case png
        /// The whole document, as a PDF. Pro.
        case pdf

        public var id: Self { self }

        public var fileExtension: String {
            switch self {
            case .png: return "png"
            case .pdf: return "pdf"
            }
        }

        public var displayName: String {
            switch self {
            case .png: return String(localized: "PNG image", comment: "Export format: a single-page image")
            case .pdf: return String(localized: "PDF", comment: "Export format: a multi-page document")
            }
        }

        public var requiresPro: Bool { self == .pdf }
    }

    /// The formats a session can be exported as, given the tier.
    ///
    /// An image source has no PDF option on any tier — wrapping one photo in a PDF is a container
    /// change, not a feature, and offering it as a Pro unlock would be a lie about what Pro buys.
    public static func availableFormats(for source: SessionSource, tier: Tier) -> [Format] {
        guard source.isPDF else { return [.png] }
        return tier.isPro ? [.pdf, .png] : [.png]
    }

    // MARK: - Progress

    /// Coarse, honest progress.
    ///
    /// The fractions are stage boundaries, not interpolation. `RedactionEngine` redacts a whole
    /// document in one call, so there is no truthful per-page number to report from inside it, and
    /// a timer-driven bar that creeps to 90% while nothing happens is a lie the user can feel.
    public struct Progress: Sendable, Hashable {
        public enum Stage: Sendable, Hashable {
            case preparing
            case destroying
            case saving
            case finished

            public var description: String {
                switch self {
                case .preparing:
                    return String(localized: "Preparing…", comment: "Export progress: gathering the pages to redact")
                case .destroying:
                    return String(localized: "Removing information permanently…", comment: "Export progress: running the redaction engine")
                case .saving:
                    return String(localized: "Saving to your library…", comment: "Export progress: writing the finished file")
                case .finished:
                    return String(localized: "Done.", comment: "Export progress: the export finished")
                }
            }
        }

        public let stage: Stage
        public let fraction: Double

        public init(stage: Stage) {
            self.stage = stage
            switch stage {
            case .preparing:  fraction = 0.1
            case .destroying: fraction = 0.35
            case .saving:     fraction = 0.85
            case .finished:   fraction = 1
            }
        }
    }

    // MARK: - Result

    /// A finished export.
    public struct Artifact: Sendable, Hashable {
        /// Identifier of the saved `RedactedDocument`, for `AppCoordinator.finish(savedDocumentID:)`.
        public let documentID: UUID
        /// On-disk location of the redacted file, for sharing. It is inside the vault, so it is
        /// file-protected and excluded from backup like everything else derived.
        public let fileURL: URL
        public let format: Format
        /// Number of regions actually burned in.
        public let redactionCount: Int
        /// Pages whose inherited markup was baked into pixels at the user's request.
        public let flattenedPageIndices: [Int]
        /// Suggested filename for the share sheet.
        public let fileName: String
    }

    // MARK: - Flatten request

    /// The user's answer to the insecure-markup warning: which pages to bake into pixels.
    ///
    /// Empty means "leave everything as it is" — a legitimate choice, and one the export honours
    /// without argument.
    public typealias FlattenSelection = Set<Int>

    // MARK: - Export

    /// Runs the export and saves the result.
    ///
    /// - Parameters:
    ///   - session: the document being exported. Its `source` bytes are read, never written.
    ///   - format: chosen encoding. Must be in ``availableFormats(for:tier:)``.
    ///   - tier: what the user is entitled to.
    ///   - pagesToFlatten: page indices whose existing markup the user asked to make permanent.
    ///   - store: where the finished document is recorded.
    ///   - usage: the free-tier counter. Incremented **after** success, so a failed or cancelled
    ///     export never costs the user a document.
    ///   - vault: on-disk storage for the file.
    ///   - onProgress: called on the main actor at each stage boundary.
    /// - Throws: ``ExportError`` for anything the user can act on; `CancellationError` if the
    ///   calling task was cancelled. Cancellation happens before or between stages and leaves
    ///   nothing behind: no vault file, no store record, no quota consumed.
    @MainActor
    @discardableResult
    public static func run(
        session: RedactionSession,
        format: Format,
        tier: Tier,
        pagesToFlatten: FlattenSelection = [],
        store: DocumentStore,
        usage: UsageTracker = .shared,
        vault: FileVault = .shared,
        onProgress: @MainActor (Progress) -> Void = { _ in }
    ) async throws -> Artifact {

        onProgress(Progress(stage: .preparing))

        guard availableFormats(for: session.source, tier: tier).contains(format) else {
            throw ExportError.formatRequiresPro(format)
        }
        guard tier.isPro || usage.canProcessDocument() else {
            throw ExportError.freeAllowanceSpent(resetsOn: usage.nextResetDate)
        }
        guard !session.pages.isEmpty else { throw ExportError.nothingToExport }

        let pageIndex = session.currentPageIndex
        let sourceData = session.source.data
        let isPDF = session.source.isPDF
        let title = session.title
        let redactionCount = session.activeRedactionCount

        // Everything the engine needs is captured as `Sendable` values here, on the main actor,
        // before any work is detached. Nothing reaches back into the session from the detached
        // task, so there is no way for a mid-export edit to change what gets destroyed.
        let payload: Payload
        switch format {
        case .pdf:
            payload = .pdf(
                data: sourceData,
                redactions: pageRedactions(for: session, flattening: pagesToFlatten)
            )
        case .png:
            guard let page = session.pages.first(where: { $0.index == pageIndex }) else {
                throw ExportError.nothingToExport
            }
            payload = .image(data: page.imageData, regions: session.activeRegions(onPage: pageIndex))
        }

        let auditKinds: [(kind: String, pageIndex: Int)] = tier.isPro
            ? session.detected
                .filter { session.isEnabled($0) }
                .map { (kindIdentifier(for: $0.pii.kind), $0.pageIndex) }
            : []

        try Task.checkCancellation()
        onProgress(Progress(stage: .destroying))

        let produced = try await Task.detached(priority: .userInitiated) {
            try produce(payload)
        }.value

        try Task.checkCancellation()
        onProgress(Progress(stage: .saving))

        let thumbnailData = await Task.detached(priority: .utility) {
            thumbnail(for: produced, format: format)
        }.value

        let vaultCopy = vault
        let stored = try await Task.detached(priority: .userInitiated) { () throws -> StoredFiles in
            let filePath = try vaultCopy.write(produced, kind: .pages, fileExtension: format.fileExtension)
            let thumbnailPath = try thumbnailData.map {
                try vaultCopy.write($0, kind: .thumbnails, fileExtension: "png")
            }
            return StoredFiles(filePath: filePath, thumbnailPath: thumbnailPath)
        }.value

        // Past this point the bytes exist on disk. Cancelling now would orphan them, so the
        // remaining work — a store insert and a counter bump — runs to completion.
        let document = RedactedDocument(
            title: title,
            sourceKind: isPDF ? .pdf : .photo,
            pageCount: format == .pdf ? session.pages.count : 1,
            thumbnailPath: stored.thumbnailPath,
            redactionCount: redactionCount,
            pagePaths: [stored.filePath]
        )
        try store.insert(document)

        if !auditKinds.isEmpty {
            try store.appendAuditRecords(
                auditKinds.map { RedactionRecord(kindIdentifier: $0.kind, pageIndex: $0.pageIndex) },
                to: document
            )
        }

        usage.recordDocumentProcessed()
        onProgress(Progress(stage: .finished))

        return Artifact(
            documentID: document.id,
            fileURL: try vault.url(forRelativePath: stored.filePath),
            format: format,
            redactionCount: redactionCount,
            flattenedPageIndices: pagesToFlatten.sorted(),
            fileName: fileName(for: title, format: format)
        )
    }

    // MARK: - Preview

    /// Produces the pixels the export screen shows: the current page, already redacted.
    ///
    /// The preview goes through `RedactionEngine` rather than drawing bars in a SwiftUI overlay so
    /// that what the user inspects **is** the output. A preview drawn separately can agree with the
    /// export today and drift from it tomorrow, and the direction it drifts in is a bar that looks
    /// right on screen and lands elsewhere in the file.
    public static func previewImageData(
        pageData: Data,
        regions: [RedactionRegion]
    ) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try RedactionEngine.redactedImageData(from: pageData, regions: regions, format: .png)
        }.value
    }

    // MARK: - Page redactions, including flattening

    /// The session's own redactions, plus a flatten instruction for each page the user asked to
    /// make permanent.
    ///
    /// The flatten instruction is a **zero-sized region**. That is not a hack looking for a comment:
    /// `RedactionEngine.redactedPDFData` rasterises any page that carries at least one region and
    /// passes every other page through verbatim, and `burnBars` skips regions whose pixel rect is
    /// empty. So a zero-sized region says exactly "rebuild this page from pixels, destroy nothing
    /// extra" — which is precisely what making inherited markup permanent means, expressed through
    /// the one audited destroy path instead of a second rasteriser written here.
    @MainActor
    static func pageRedactions(
        for session: RedactionSession,
        flattening pagesToFlatten: FlattenSelection
    ) -> [PageRedaction] {
        var byPage: [Int: [RedactionRegion]] = [:]
        for redaction in session.pageRedactions() {
            byPage[redaction.pageIndex, default: []] += redaction.regions
        }
        for pageIndex in pagesToFlatten where byPage[pageIndex] == nil {
            byPage[pageIndex] = [flattenOnlyRegion]
        }
        return byPage
            .sorted { $0.key < $1.key }
            .map { PageRedaction(pageIndex: $0.key, regions: $0.value) }
    }

    /// See ``pageRedactions(for:flattening:)``. Zero size, so it destroys nothing by itself.
    static let flattenOnlyRegion = RedactionRegion(rect: .zero)

    // MARK: - Work

    private enum Payload: Sendable {
        case image(data: Data, regions: [RedactionRegion])
        case pdf(data: Data, redactions: [PageRedaction])
    }

    private struct StoredFiles: Sendable {
        let filePath: String
        let thumbnailPath: String?
    }

    private static func produce(_ payload: Payload) throws -> Data {
        switch payload {
        case .image(let data, let regions):
            return try RedactionEngine.redactedImageData(from: data, regions: regions, format: .png)
        case .pdf(let data, let redactions):
            return try RedactionEngine.redactedPDFData(from: data, redactions: redactions)
        }
    }

    /// A small library thumbnail, rendered from the **redacted** bytes.
    ///
    /// Never from the source: a thumbnail is the one artefact that gets shown in a list, in a
    /// screenshot, and over a shoulder, and a library preview still showing the unredacted page
    /// would defeat the entire product on the most visible surface it has.
    private static func thumbnail(for data: Data, format: Format) -> Data? {
        let image: UIImage?
        switch format {
        case .png:
            image = UIImage(data: data)
        case .pdf:
            image = firstPageImage(ofPDF: data)
        }
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }

        let maxEdge: CGFloat = 320
        let scale = min(1, maxEdge / max(image.size.width, image.size.height))
        let target = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        guard target.width >= 1, target.height >= 1 else { return nil }

        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }.pngData()
    }

    private static func firstPageImage(ofPDF data: Data) -> UIImage? {
        guard
            let provider = CGDataProvider(data: data as CFData),
            let document = CGPDFDocument(provider),
            let page = document.page(at: 1)
        else { return nil }

        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }

        let renderer = UIGraphicsImageRenderer(size: box.size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: box.size))
            // CoreGraphics draws PDF pages bottom-up; the transform below is the standard
            // PDF-to-UIKit flip and belongs to the renderer, not to any redaction geometry.
            context.cgContext.translateBy(x: 0, y: box.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            context.cgContext.drawPDFPage(page)
        }
    }

    // MARK: - Naming

    private static func fileName(for title: String, format: Format) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty
            ? String(localized: "Redacted", comment: "Fallback filename for an exported document with no title")
            : trimmed
        let safe = base.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        return "\(safe).\(format.fileExtension)"
    }

    /// Stable string identifier for the audit log.
    ///
    /// `RedactionRecord.kindIdentifier` is a `String` on purpose: the persisted store must survive
    /// `PIIKind` gaining or renaming cases. This mapping is therefore explicit rather than derived
    /// from `String(describing:)`, whose output changes if a case is renamed.
    static func kindIdentifier(for kind: PIIKind) -> String {
        switch kind {
        case .personName:   return "personName"
        case .organisation: return "organisation"
        case .place:        return "place"
        case .email:        return "email"
        case .phone:        return "phone"
        case .pan:          return "pan"
        case .aadhaar:      return "aadhaar"
        case .ifsc:         return "ifsc"
        case .bankAccount:  return "bankAccount"
        case .gstin:        return "gstin"
        case .creditCard:   return "creditCard"
        case .dateOfBirth:  return "dateOfBirth"
        case .address:      return "address"
        case .custom(let name): return "custom:\(name)"
        }
    }

    // MARK: - Errors

    /// Every case has a recovery path on screen — no export failure is a dead end
    /// (App Review checklist, `CLAUDE.md`).
    public enum ExportError: Error, Sendable, Equatable, LocalizedError {
        case nothingToExport
        case formatRequiresPro(Format)
        case freeAllowanceSpent(resetsOn: Date)

        public var errorDescription: String? {
            switch self {
            case .nothingToExport:
                return String(localized: "There are no pages to export.",
                              comment: "Error shown when an export is attempted with no rendered pages")
            case .formatRequiresPro(let format):
                return String(localized: "\(format.displayName) export is part of Redact Pro.",
                              comment: "Error shown when a free user picks a Pro export format")
            case .freeAllowanceSpent:
                return String(localized: "You have used all \(UsageTracker.freeMonthlyAllowance) free documents this month.",
                              comment: "Error shown when the free monthly quota is exhausted")
            }
        }

        public var recoverySuggestion: String? {
            switch self {
            case .nothingToExport:
                return String(localized: "Go back and add a document.",
                              comment: "Recovery suggestion when there is nothing to export")
            case .formatRequiresPro:
                return String(localized: "Export a single page as a PNG image, or see what Pro includes.",
                              comment: "Recovery suggestion when a Pro format is picked on the free tier")
            case .freeAllowanceSpent(let resetsOn):
                let date = resetsOn.formatted(date: .abbreviated, time: .omitted)
                return String(localized: "Your free documents come back on \(date). Pro removes the limit.",
                              comment: "Recovery suggestion when the free quota is exhausted; parameter is a date")
            }
        }
    }
}
