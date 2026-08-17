import Foundation
import Observation
import SwiftUI

/// State and intents for the library screen.
///
/// ## Why deletion is deferred rather than undone
///
/// Deleting a document purges its page renders and thumbnail from disk
/// (`DocumentStore.delete(_:)` → `FileVault.delete(relativePaths:)`), and that is the
/// point: a privacy app that leaves the bytes behind has not deleted anything. But
/// destroyed files cannot be restored, so a real undo is impossible *after* the purge.
///
/// So the delete is **staged**, not reversed. A deleted document is hidden from the
/// list immediately, and the store call happens ``LibraryLayout/undoWindow`` seconds
/// later. Undo cancels the pending call; it never resurrects anything. The window is
/// closed early — and the delete committed — whenever the screen goes away or the app
/// leaves the foreground, so "I deleted it" is true the moment the user stops looking.
///
/// The alternative, deleting immediately and offering no undo, means a modal
/// confirmation on every swipe. That trains people to dismiss confirmations, which is
/// how the wrong document actually gets deleted.
@MainActor
@Observable
final class LibraryModel {

    /// A staged delete awaiting either its timer or an undo.
    struct PendingDeletion: Identifiable, Equatable {
        let id = UUID()
        let documentIDs: [UUID]
        /// Snackbar copy, e.g. "Salary slip deleted" / "3 documents deleted".
        let message: String
    }

    // MARK: - State

    private(set) var documents: [DocumentSummary] = []
    private(set) var hasLoaded = false

    /// A user-facing failure message, or `nil`. Never a raw `Error` description —
    /// the screen has to be able to say something a person can act on.
    private(set) var failureMessage: String?

    var searchText = ""
    var selection: Set<UUID> = []

    private(set) var pendingDeletion: PendingDeletion?

    /// Ids hidden from the list because a delete is staged for them.
    private var stagedIDs: Set<UUID> = []
    private var commitTask: Task<Void, Never>?

    private var store: DocumentStore?

    // MARK: - Derived

    /// What the list actually renders: staged deletions removed, search applied.
    var visibleDocuments: [DocumentSummary] {
        documents
            .filter { !stagedIDs.contains($0.id) }
            .filter { $0.matches(searchText) }
    }

    /// True when the library is genuinely empty, as opposed to filtered to nothing.
    /// Those need different screens — one offers a scan, the other offers a reset.
    var isLibraryEmpty: Bool {
        hasLoaded && documents.allSatisfy { stagedIDs.contains($0.id) }
    }

    var isSearchEmpty: Bool {
        hasLoaded && !isLibraryEmpty && visibleDocuments.isEmpty
    }

    // MARK: - Wiring

    /// Binds the store from the environment. Idempotent — `.task` runs again after a
    /// back-navigation and must not tear down state that is still on screen.
    func attach(store: DocumentStore) {
        guard self.store !== store else { return }
        self.store = store
    }

    // MARK: - Loading

    func reload() {
        guard let store else { return }
        do {
            documents = try store.documents(order: .newestFirst).map(DocumentSummary.init)
            failureMessage = nil
        } catch {
            documents = []
            failureMessage = String(
                localized: "Your documents could not be opened. Reopening the app usually fixes this.",
                comment: "Library error: the document store could not be read"
            )
        }
        hasLoaded = true
    }

    // MARK: - Selection

    func clearSelection() {
        selection.removeAll()
    }

    var selectedSummaries: [DocumentSummary] {
        documents.filter { selection.contains($0.id) }
    }

    // MARK: - Deletion

    /// Stages the deletion of one document and starts the undo window.
    func stageDelete(_ summary: DocumentSummary) {
        stage(ids: [summary.id], message: Self.singleDeleteMessage(title: summary.title))
    }

    /// Stages the deletion of the current multi-selection.
    func stageDeleteSelection() {
        let summaries = selectedSummaries
        guard !summaries.isEmpty else { return }
        let message = summaries.count == 1
            ? Self.singleDeleteMessage(title: summaries[0].title)
            : String(localized: "\(summaries.count) documents deleted",
                     comment: "Snackbar: several documents were deleted")
        stage(ids: summaries.map(\.id), message: message)
        clearSelection()
    }

    /// The title is substituted with `%@` rather than interpolated into the
    /// `String(localized:)` key. A key that varies with a document's name is a key that
    /// can never be found in a strings table.
    private static func singleDeleteMessage(title: String) -> String {
        String(
            format: String(localized: "%@ deleted",
                           comment: "Snackbar: one named document was deleted. %@ is its title."),
            title
        )
    }

    private func stage(ids: [UUID], message: String) {
        // Only one undo window at a time. A second delete commits the first, so the
        // snackbar always refers to the action the user just took.
        commitPendingDeletionNow()

        stagedIDs.formUnion(ids)
        let pending = PendingDeletion(documentIDs: ids, message: message)
        pendingDeletion = pending

        commitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(LibraryLayout.undoWindow * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.commit(pending)
        }
    }

    /// Cancels the staged delete. Nothing has been purged yet, so this is a plain
    /// un-hide rather than a restore.
    func undoPendingDeletion() {
        guard let pending = pendingDeletion else { return }
        commitTask?.cancel()
        commitTask = nil
        stagedIDs.subtract(pending.documentIDs)
        pendingDeletion = nil
    }

    /// Commits any staged delete immediately.
    ///
    /// Called when the screen disappears and when the app leaves the foreground: a
    /// pending purge must not survive as an invisible promise. Without this, force-
    /// quitting during the undo window leaves the files on disk forever.
    func commitPendingDeletionNow() {
        guard let pending = pendingDeletion else { return }
        commitTask?.cancel()
        commitTask = nil
        commit(pending)
    }

    /// The single place that actually destroys anything.
    private func commit(_ pending: PendingDeletion) {
        // Guard against a cancelled timer racing an explicit commit.
        guard pendingDeletion?.id == pending.id else { return }
        pendingDeletion = nil
        commitTask = nil

        guard let store else {
            stagedIDs.subtract(pending.documentIDs)
            return
        }

        do {
            // `DocumentStore.delete` purges the vault files *before* removing the row,
            // so an interrupted delete leaves a visible record with missing files
            // rather than files no record points at. Orphans in a privacy app are a
            // real leak; this feature must never route around that method.
            try store.delete(ids: pending.documentIDs)
            documents.removeAll { pending.documentIDs.contains($0.id) }
            ThumbnailLoader.shared.evictAll()
            failureMessage = nil
        } catch {
            // Nothing was removed — put the documents back so the user is not left
            // believing they are gone.
            failureMessage = String(
                localized: "Those documents could not be deleted. Nothing was removed.",
                comment: "Library error: deletion failed and the documents remain"
            )
        }

        stagedIDs.subtract(pending.documentIDs)
    }
}
