import Foundation
import SwiftData

/// Where a document originally came from. Persisted as `rawValue`, so cases may be
/// added but existing raw values must never change.
public enum DocumentSourceKind: String, Codable, Sendable, CaseIterable {
    case photo
    case scan
    case pdf
}

/// A document the user has redacted.
///
/// Storage rule: **no image bytes live here.** `thumbnailPath` and each page's
/// `renderedPagePath` are paths *relative to* ``FileVault/root``, never absolute
/// URLs. The app container's UUID changes between installs and OS upgrades, so a
/// persisted absolute path dangles on the next launch — one of the most common iOS
/// data bugs, and invisible until a user updates.
///
/// `CLAUDE.md` rule 1: this model is local-only. No CloudKit, no `.cloudKitDatabase`
/// on the container, no sync of any kind.
@Model
public final class RedactedDocument {

    /// Stable identity independent of SwiftData's `PersistentIdentifier`, which is
    /// not safe to hand across actor boundaries or persist outside the store.
    @Attribute(.unique) public var id: UUID

    public var createdAt: Date
    public var title: String

    /// Backing storage for ``sourceKind``. SwiftData indexes and sorts on stored
    /// primitives; a raw `String` keeps predicates usable.
    public var sourceKindRaw: String

    public var pageCount: Int

    /// Vault-relative path of the list thumbnail, or `nil` if none was produced.
    public var thumbnailPath: String?

    /// Denormalised count so the library list never has to fault in the audit trail
    /// just to draw a badge.
    public var redactionCount: Int

    /// Vault-relative paths of every rendered page belonging to this document.
    /// Deleting the document must delete these — see ``DocumentStore/delete(_:)``.
    public var pagePaths: [String]

    /// Per-redaction audit trail. Pro-tier feature; empty on free-tier documents
    /// because the audit log is not recorded for them.
    @Relationship(deleteRule: .cascade, inverse: \RedactionRecord.document)
    public var auditTrail: [RedactionRecord]

    public var sourceKind: DocumentSourceKind {
        get { DocumentSourceKind(rawValue: sourceKindRaw) ?? .photo }
        set { sourceKindRaw = newValue.rawValue }
    }

    /// Every vault-relative path this document owns, for purge-on-delete.
    public var ownedFilePaths: [String] {
        pagePaths + [thumbnailPath].compactMap { $0 }
    }

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        title: String,
        sourceKind: DocumentSourceKind,
        pageCount: Int,
        thumbnailPath: String? = nil,
        redactionCount: Int = 0,
        pagePaths: [String] = [],
        auditTrail: [RedactionRecord] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.sourceKindRaw = sourceKind.rawValue
        self.pageCount = pageCount
        self.thumbnailPath = thumbnailPath
        self.redactionCount = redactionCount
        self.pagePaths = pagePaths
        self.auditTrail = auditTrail
    }
}

/// One redaction that was applied: what kind of PII, on which page, when.
///
/// This backs the Pro-tier redaction audit log. It deliberately records **no
/// sample of the redacted text** — storing "the last four digits we removed" would
/// re-introduce the PII we just destroyed, defeating `CLAUDE.md` rule 2.
@Model
public final class RedactionRecord {

    @Attribute(.unique) public var id: UUID

    /// Identifier of the detected PII category, e.g. `"aadhaar"`, `"emailAddress"`.
    ///
    /// Stored as a string rather than importing the detection layer's `PIIKind`
    /// enum: the persisted store must survive that enum gaining, renaming, or
    /// reordering cases. The display name is resolved at read time by the layer
    /// that owns the taxonomy.
    public var kindIdentifier: String

    /// Zero-based page index within the parent document.
    public var pageIndex: Int

    public var redactedAt: Date

    public var document: RedactedDocument?

    public init(
        id: UUID = UUID(),
        kindIdentifier: String,
        pageIndex: Int,
        redactedAt: Date = .now,
        document: RedactedDocument? = nil
    ) {
        self.id = id
        self.kindIdentifier = kindIdentifier
        self.pageIndex = pageIndex
        self.redactedAt = redactedAt
        self.document = document
    }
}

/// The app's SwiftData schema and container factory.
public enum PersistenceSchema {

    public static let models: [any PersistentModel.Type] = [
        RedactedDocument.self,
        RedactionRecord.self
    ]

    /// Builds the on-device container.
    ///
    /// `cloudKitDatabase: .none` is explicit rather than defaulted, so that a future
    /// edit enabling sync has to delete a line that says why it must not.
    /// See [[DEC-004-no-network]].
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Redact",
            schema: Schema(models),
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: Schema(models), configurations: [configuration])
    }
}
