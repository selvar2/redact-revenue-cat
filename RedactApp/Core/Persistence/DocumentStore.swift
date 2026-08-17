import Foundation
import Observation
import SwiftData

/// Main-actor facade over the SwiftData `ModelContext`.
///
/// `@Model` types are not `Sendable`, so they may only be touched on one actor.
/// Pinning the whole store to `@MainActor` is what makes that safe under Swift 6
/// strict concurrency without a single `@unchecked Sendable` — the views that read
/// these objects are `@MainActor` anyway, so nothing is lost.
///
/// Heavy work (rendering, OCR) happens off this actor and hands back `Data`; only
/// the cheap store mutation comes back here.
@MainActor
@Observable
public final class DocumentStore {

    public enum StoreError: Error, Equatable, Sendable {
        case notFound(UUID)
    }

    /// Fetch ordering for the library list.
    public enum SortOrder: Sendable {
        case newestFirst
        case oldestFirst
        case titleAscending

        var descriptors: [SortDescriptor<RedactedDocument>] {
            switch self {
            case .newestFirst: [SortDescriptor(\.createdAt, order: .reverse)]
            case .oldestFirst: [SortDescriptor(\.createdAt, order: .forward)]
            case .titleAscending: [SortDescriptor(\.title, order: .forward)]
            }
        }
    }

    private let context: ModelContext
    private let vault: FileVault

    public init(context: ModelContext, vault: FileVault = .shared) {
        self.context = context
        self.vault = vault
    }

    public convenience init(container: ModelContainer, vault: FileVault = .shared) {
        self.init(context: ModelContext(container), vault: vault)
    }

    // MARK: - Fetching

    /// Fetches a page of documents.
    ///
    /// - Parameters:
    ///   - order: sort applied in the store, not in memory — the library can hold
    ///     hundreds of documents and sorting after fetching would load them all.
    ///   - limit: page size. `nil` fetches everything.
    ///   - offset: number of rows to skip.
    public func documents(
        order: SortOrder = .newestFirst,
        limit: Int? = nil,
        offset: Int = 0
    ) throws -> [RedactedDocument] {
        var descriptor = FetchDescriptor<RedactedDocument>(sortBy: order.descriptors)
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        return try context.fetch(descriptor)
    }

    public func document(id: UUID) throws -> RedactedDocument? {
        var descriptor = FetchDescriptor<RedactedDocument>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func documentCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<RedactedDocument>())
    }

    // MARK: - Inserting

    /// Inserts a document and saves immediately.
    ///
    /// The save is not deferred: the caller has already written page files to the
    /// vault, and a crash before save would leave those files orphaned.
    public func insert(_ document: RedactedDocument) throws {
        context.insert(document)
        try context.save()
    }

    /// Appends audit records to an existing document and refreshes its denormalised
    /// ``RedactedDocument/redactionCount``.
    public func appendAuditRecords(_ records: [RedactionRecord], to document: RedactedDocument) throws {
        for record in records {
            record.document = document
            context.insert(record)
        }
        document.auditTrail.append(contentsOf: records)
        document.redactionCount = document.auditTrail.count
        try context.save()
    }

    // MARK: - Deleting

    /// Deletes a document **and every file it owns**.
    ///
    /// Files are purged before the record is removed: if the process dies between
    /// the two, the next launch sees a record whose files are gone (recoverable,
    /// visible) rather than files no record points at (invisible, and in a privacy
    /// app an actual leak of content the user believes is deleted).
    public func delete(_ document: RedactedDocument) throws {
        try vault.delete(relativePaths: document.ownedFilePaths)
        context.delete(document)
        try context.save()
    }

    public func delete(ids: [UUID]) throws {
        for id in ids {
            guard let document = try document(id: id) else { throw StoreError.notFound(id) }
            try delete(document)
        }
    }

    /// Deletes every document and empties the vault. Backs "Delete all data" in
    /// settings — a privacy app must be able to prove it can forget everything.
    public func deleteAll() throws {
        for document in try documents(limit: nil) {
            try vault.delete(relativePaths: document.ownedFilePaths)
            context.delete(document)
        }
        try context.save()
        try vault.purgeOrphans(referencedRelativePaths: [])
    }

    // MARK: - Maintenance

    /// Removes vault files no document references. Run once at launch.
    /// - Returns: the number of orphaned files deleted.
    @discardableResult
    public func purgeOrphanedFiles() throws -> Int {
        let referenced = try documents(limit: nil).reduce(into: Set<String>()) { set, document in
            set.formUnion(document.ownedFilePaths)
        }
        return try vault.purgeOrphans(referencedRelativePaths: referenced)
    }
}
