import Foundation
import Observation
import SwiftData

/// Everything the app has to stand up before the first frame, and the honest record of whether it
/// worked.
///
/// Launch does three things that Phase 1 built but nothing called: prepare the file vault, open the
/// SwiftData container, and delete vault files no document references any more. That last one
/// matters more here than in most apps — an orphaned file in this vault is a page of somebody's
/// unredacted salary slip that survived the document being deleted.
///
/// None of the three is allowed to crash the app. A device that is out of disk, or a store that
/// failed to migrate, still has a working redaction engine; refusing to launch would take away the
/// one thing the user came for. Instead the failure is recorded in ``storageIsTemporary`` and shown
/// on the home screen, because a silent fallback to in-memory storage would look like the app
/// losing documents for no reason (CLAUDE.md rule 10: no dead ends, no lies).
@Observable
@MainActor
public final class AppEnvironment {

    /// The SwiftData container injected into the view hierarchy.
    public let container: ModelContainer

    /// Main-actor facade the features use. One instance, so the library and the export screen see
    /// the same unsaved changes.
    public let store: DocumentStore

    /// True when the on-disk store could not be opened and documents are being held in memory only.
    /// Surfaced in the UI; never swallowed.
    public private(set) var storageIsTemporary = false

    /// How many orphaned vault files launch cleaned up. Kept for the memory/diagnostics story
    /// rather than the UI — a non-zero value here after a normal run means a delete path leaked.
    public private(set) var orphanedFilesPurged = 0

    public init() {
        var temporary = false
        let container: ModelContainer
        do {
            container = try PersistenceSchema.makeContainer()
        } catch {
            temporary = true
            do {
                // Second chance in memory. If even this throws, the schema itself is malformed —
                // a programmer error present in every build, not a runtime condition, and not
                // something a user could act on.
                container = try PersistenceSchema.makeContainer(inMemory: true)
            } catch {
                preconditionFailure("The SwiftData schema cannot be instantiated: \(error)")
            }
        }

        self.container = container
        self.store = DocumentStore(container: container)
        self.storageIsTemporary = temporary
    }

    /// Prepares the vault and clears orphans. Called once, from the root view's `.task`.
    ///
    /// Separate from `init` so the work happens after the first frame is on screen: neither step is
    /// needed to draw the home screen, and doing them in the initialiser adds directory creation
    /// and a full fetch to launch time for no benefit.
    public func prepareStorage() {
        do {
            try FileVault.shared.prepare()
        } catch {
            // The vault is unusable, so exports will not be saveable. Flagging it with the same
            // banner is correct: from the user's side both failures mean "documents will not be
            // kept", and offering two different explanations of the same outcome helps nobody.
            storageIsTemporary = true
        }

        do {
            orphanedFilesPurged = try store.purgeOrphanedFiles()
        } catch {
            // Purging is maintenance. Failing it leaves disk in exactly the state it was already
            // in, so there is nothing to tell the user and nothing to retry.
        }
    }
}
