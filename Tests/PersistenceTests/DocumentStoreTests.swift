import Foundation
import SwiftData
import XCTest

@testable import RedactApp

/// F05's acceptance criterion is "documents persist across launch; delete removes all derived
/// files". Both halves are asserted here against real stores — an on-disk container reopened from
/// scratch for the persistence claim, and a real `FileVault` rooted in a temp directory for the
/// delete claim. Neither can be satisfied by code that has only ever compiled.
@MainActor
final class DocumentStoreTests: XCTestCase {

    /// Creates a real vault in a unique temp directory and registers its teardown.
    ///
    /// Built per test rather than in `setUpWithError`: that override is not main-actor isolated
    /// even on a `@MainActor` case, so touching stored state from it would need an unsafe opt-out
    /// that `CLAUDE.md` rule 5 forbids. `addTeardownBlock` gets the same cleanup with none of that.
    private func makeVault() throws -> FileVault {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("RedactVaultTests-\(UUID().uuidString)", isDirectory: true)
        let vault = FileVault(root: root)
        try vault.prepare()
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: root.path) {
                try? FileManager.default.removeItem(at: root)
            }
        }
        return vault
    }

    // MARK: - Helpers

    private func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "RedactTests-\(UUID().uuidString)",
            schema: Schema(PersistenceSchema.models),
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: Schema(PersistenceSchema.models), configurations: [configuration])
    }

    /// An on-disk container at a caller-controlled URL, so a second container over the same file
    /// reproduces what a relaunch actually does: a fresh process reading a store written earlier.
    private func makeOnDiskContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: Schema(PersistenceSchema.models),
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: Schema(PersistenceSchema.models), configurations: [configuration])
    }

    // MARK: - Round trip

    func testInsertedDocumentIsFetchedBack() throws {
        let vault = try makeVault()
        let store = DocumentStore(container: try makeInMemoryContainer(), vault: vault)
        let id = UUID()

        try store.insert(
            RedactedDocument(
                id: id,
                title: "Passport scan",
                sourceKind: .scan,
                pageCount: 2,
                redactionCount: 3
            )
        )

        XCTAssertEqual(try store.documentCount(), 1)
        let fetched = try XCTUnwrap(try store.document(id: id))
        XCTAssertEqual(fetched.title, "Passport scan")
        XCTAssertEqual(fetched.sourceKind, .scan)
        XCTAssertEqual(fetched.pageCount, 2)
        XCTAssertEqual(fetched.redactionCount, 3)
    }

    func testDocumentsAreSortedNewestFirst() throws {
        let vault = try makeVault()
        let store = DocumentStore(container: try makeInMemoryContainer(), vault: vault)
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)

        try store.insert(RedactedDocument(createdAt: old, title: "Older", sourceKind: .pdf, pageCount: 1))
        try store.insert(RedactedDocument(createdAt: new, title: "Newer", sourceKind: .pdf, pageCount: 1))

        XCTAssertEqual(try store.documents(order: .newestFirst).map(\.title), ["Newer", "Older"])
        XCTAssertEqual(try store.documents(order: .oldestFirst).map(\.title), ["Older", "Newer"])
    }

    func testAuditRecordsAttachAndUpdateDenormalisedCount() throws {
        let vault = try makeVault()
        let store = DocumentStore(container: try makeInMemoryContainer(), vault: vault)
        let document = RedactedDocument(title: "Bank statement", sourceKind: .pdf, pageCount: 1)
        try store.insert(document)

        try store.appendAuditRecords(
            [
                RedactionRecord(kindIdentifier: "aadhaar", pageIndex: 0),
                RedactionRecord(kindIdentifier: "emailAddress", pageIndex: 0)
            ],
            to: document
        )

        let fetched = try XCTUnwrap(try store.document(id: document.id))
        XCTAssertEqual(fetched.redactionCount, 2)
        XCTAssertEqual(Set(fetched.auditTrail.map(\.kindIdentifier)), ["aadhaar", "emailAddress"])
    }

    // MARK: - Persistence across launch

    /// The literal F05 criterion. The first container is torn down completely before the second is
    /// opened, so nothing but the file on disk carries the document across.
    func testDocumentSurvivesContainerTeardownAndReopen() throws {
        let vault = try makeVault()
        let storeURL = vault.root.appendingPathComponent("relaunch.store")
        let id = UUID()

        do {
            let store = DocumentStore(container: try makeOnDiskContainer(at: storeURL), vault: vault)
            try store.insert(
                RedactedDocument(id: id, title: "Aadhaar card", sourceKind: .photo, pageCount: 1)
            )
        }

        let reopened = DocumentStore(container: try makeOnDiskContainer(at: storeURL), vault: vault)
        let recovered = try XCTUnwrap(
            try reopened.document(id: id),
            "The document did not survive a container reopen — F05's persistence claim is false."
        )
        XCTAssertEqual(recovered.title, "Aadhaar card")
        XCTAssertEqual(recovered.sourceKind, .photo)
    }

    // MARK: - Delete removes derived files

    func testDeleteRemovesDocumentAndItsVaultFiles() throws {
        let vault = try makeVault()
        let store = DocumentStore(container: try makeInMemoryContainer(), vault: vault)

        let pagePath = try vault.write(Data("page".utf8), kind: .pages, fileExtension: "png")
        let thumbnailPath = try vault.write(Data("thumb".utf8), kind: .thumbnails, fileExtension: "png")
        XCTAssertTrue(vault.fileExists(atRelativePath: pagePath))
        XCTAssertTrue(vault.fileExists(atRelativePath: thumbnailPath))

        let document = RedactedDocument(
            title: "Payslip",
            sourceKind: .pdf,
            pageCount: 1,
            thumbnailPath: thumbnailPath,
            pagePaths: [pagePath]
        )
        try store.insert(document)
        try store.delete(document)

        XCTAssertEqual(try store.documentCount(), 0)
        XCTAssertFalse(
            vault.fileExists(atRelativePath: pagePath),
            "Page render survived delete — the bytes the user believes are gone are still readable."
        )
        XCTAssertFalse(
            vault.fileExists(atRelativePath: thumbnailPath),
            "Thumbnail survived delete."
        )
    }

    func testDeleteAllEmptiesStoreAndVault() throws {
        let vault = try makeVault()
        let store = DocumentStore(container: try makeInMemoryContainer(), vault: vault)

        for index in 0..<3 {
            let path = try vault.write(Data("page\(index)".utf8), kind: .pages, fileExtension: "png")
            try store.insert(
                RedactedDocument(title: "Doc \(index)", sourceKind: .scan, pageCount: 1, pagePaths: [path])
            )
        }
        let orphan = try vault.write(Data("orphan".utf8), kind: .pages, fileExtension: "png")

        try store.deleteAll()

        XCTAssertEqual(try store.documentCount(), 0)
        XCTAssertFalse(
            vault.fileExists(atRelativePath: orphan),
            "deleteAll left an unreferenced file behind; \"delete all data\" must forget everything."
        )
    }

    func testDeleteByUnknownIDThrowsNotFound() throws {
        let vault = try makeVault()
        let store = DocumentStore(container: try makeInMemoryContainer(), vault: vault)
        let missing = UUID()

        XCTAssertThrowsError(try store.delete(ids: [missing])) { error in
            XCTAssertEqual(error as? DocumentStore.StoreError, .notFound(missing))
        }
    }

    // MARK: - Orphan sweep

    func testPurgeOrphanedFilesKeepsReferencedFiles() throws {
        let vault = try makeVault()
        let store = DocumentStore(container: try makeInMemoryContainer(), vault: vault)

        let referenced = try vault.write(Data("keep".utf8), kind: .pages, fileExtension: "png")
        try store.insert(
            RedactedDocument(title: "Kept", sourceKind: .pdf, pageCount: 1, pagePaths: [referenced])
        )
        let orphan = try vault.write(Data("drop".utf8), kind: .pages, fileExtension: "png")

        XCTAssertEqual(try store.purgeOrphanedFiles(), 1)
        XCTAssertTrue(vault.fileExists(atRelativePath: referenced))
        XCTAssertFalse(vault.fileExists(atRelativePath: orphan))
    }

    // MARK: - Vault safety

    func testVaultRefusesPathEscapingRoot() throws {
        let vault = try makeVault()
        XCTAssertThrowsError(try vault.url(forRelativePath: "../../escaped.png")) { error in
            XCTAssertEqual(
                error as? FileVault.VaultError,
                .referenceEscapesVault("../../escaped.png")
            )
        }
    }
}
