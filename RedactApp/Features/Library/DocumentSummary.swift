import Foundation

/// An immutable snapshot of one ``RedactedDocument``, for list rendering.
///
/// The library draws from value types, never from `@Model` objects directly, for two
/// reasons that both bite in practice:
///
/// - `RedactedDocument` is a SwiftData `@Model` and therefore not `Sendable`. Keeping
///   it out of view state means nothing in this feature has to reason about which
///   actor a row body is running on (`CLAUDE.md` rule 5).
/// - A row that reads a live model object faults its relationships as it scrolls.
///   `redactionCount` is denormalised on the record precisely so the list never has
///   to touch `auditTrail`; snapshotting makes that guarantee structural instead of
///   a thing each row has to remember not to do.
struct DocumentSummary: Identifiable, Hashable, Sendable {

    let id: UUID
    let title: String
    let createdAt: Date
    let sourceKind: DocumentSourceKind
    let pageCount: Int
    let redactionCount: Int

    /// Vault-relative thumbnail written at save time, or `nil`.
    let thumbnailPath: String?
    /// First rendered page — the fallback when no thumbnail was recorded.
    let firstPagePath: String?

    /// Lower-cased haystack of everything the search field matches against: the
    /// title plus several written forms of the date.
    ///
    /// Precomputed at snapshot time rather than formatted per keystroke. Formatting
    /// two hundred dates on every character typed is the difference between a search
    /// field that feels instant and one that stutters.
    let searchIndex: String

    /// What VoiceOver reads for the whole row, e.g.
    /// "Salary slip, 3 items removed, 17 August".
    let accessibilityLabel: String

    /// The artefact a row should try to draw, preferring the purpose-built thumbnail.
    var displayImagePath: String? { thumbnailPath ?? firstPagePath }

    /// Cache identity for ``ThumbnailLoader``.
    var thumbnailCacheKey: String { "row.\(id.uuidString)" }

    @MainActor
    init(_ document: RedactedDocument) {
        self.init(
            id: document.id,
            title: document.title,
            createdAt: document.createdAt,
            sourceKind: document.sourceKind,
            pageCount: document.pageCount,
            redactionCount: document.redactionCount,
            thumbnailPath: document.thumbnailPath,
            firstPagePath: document.pagePaths.first
        )
    }

    init(
        id: UUID,
        title: String,
        createdAt: Date,
        sourceKind: DocumentSourceKind,
        pageCount: Int,
        redactionCount: Int,
        thumbnailPath: String?,
        firstPagePath: String?
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.sourceKind = sourceKind
        self.pageCount = pageCount
        self.redactionCount = redactionCount
        self.thumbnailPath = thumbnailPath
        self.firstPagePath = firstPagePath
        self.searchIndex = Self.makeSearchIndex(title: title, date: createdAt)
        self.accessibilityLabel = Self.makeAccessibilityLabel(
            title: title, date: createdAt, redactionCount: redactionCount
        )
    }

    // MARK: - Derived text

    /// Date as shown on the row: relative for the last week, absolute before that.
    ///
    /// "Yesterday" is more useful than "16 August" for something made yesterday, and
    /// less useful than "16 August" for something made in March.
    var dateLabel: String {
        let daysAgo = Calendar.current.dateComponents([.day], from: createdAt, to: .now).day ?? 0
        if daysAgo < 7 {
            return createdAt.formatted(.relative(presentation: .named))
        }
        return createdAt.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// "3 removed" / "No redactions" — always a complete phrase, never a bare digit.
    var redactionLabel: String {
        redactionCount == 0
            ? String(localized: "No redactions", comment: "Library row: nothing was removed from this document")
            : String(localized: "\(redactionCount) removed", comment: "Library row: how many pieces of information were removed")
    }

    var pageLabel: String {
        pageCount == 1
            ? String(localized: "1 page", comment: "Library row: single-page document")
            : String(localized: "\(pageCount) pages", comment: "Library row: multi-page document")
    }

    // MARK: - Search and speech

    /// Matches the query against the title and against the date in several written
    /// forms, so "aug", "august", "2026" and "17/8" all find the same document.
    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }
        // Every whitespace-separated term must appear: "salary aug" narrows rather
        // than widens, which is what a search field is expected to do.
        return trimmed.split(separator: " ").allSatisfy { searchIndex.contains($0) }
    }

    private static func makeSearchIndex(title: String, date: Date) -> String {
        let forms = [
            title,
            date.formatted(.dateTime.day().month(.wide).year()),
            date.formatted(.dateTime.day().month(.abbreviated).year()),
            date.formatted(.dateTime.weekday(.wide)),
            date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        ]
        return forms.joined(separator: " ").lowercased()
    }

    private static func makeAccessibilityLabel(title: String, date: Date, redactionCount: Int) -> String {
        let spokenDate = date.formatted(.dateTime.day().month(.wide))
        let removed = redactionCount == 0
            ? String(localized: "nothing removed", comment: "VoiceOver: this document had no redactions")
            : String(localized: "\(redactionCount) items removed", comment: "VoiceOver: how many items were removed")
        return "\(title), \(removed), \(spokenDate)"
    }
}

// MARK: - Source kind presentation

extension DocumentSourceKind {

    /// Short label for the row's type pill.
    var displayName: String {
        switch self {
        case .photo: String(localized: "Photo", comment: "Document source: came from the photo library")
        case .scan:  String(localized: "Scan", comment: "Document source: captured with the camera")
        case .pdf:   String(localized: "PDF", comment: "Document source: an imported PDF")
        }
    }

    /// SF Symbol available on iOS 17.
    var symbolName: String {
        switch self {
        case .photo: "photo"
        case .scan:  "doc.viewfinder"
        case .pdf:   "doc.richtext"
        }
    }
}
