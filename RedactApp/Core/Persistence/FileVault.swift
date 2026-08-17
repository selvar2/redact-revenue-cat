import Foundation

/// On-disk storage for derived binary artefacts (page renders, thumbnails).
///
/// Why a vault instead of `Data` blobs in SwiftData: a redacted A4 page render is
/// 1–4 MB. Storing those inline makes every fetch — even a title-only library
/// listing — drag megabytes through the store's row cache. Files on disk keep the
/// SwiftData store small enough that a sorted, paginated fetch stays instant.
///
/// Why Application Support and not Documents: these are app-managed derived files.
/// `Documents` is user-visible through Files.app once `UIFileSharingEnabled` is set,
/// and Apple's data-storage guidelines reserve it for user-created content.
///
/// `CLAUDE.md` rule 1: nothing here touches the network. The vault is device-local
/// and excluded from backup, so redacted material never leaves the device — not even
/// into an iCloud or iTunes backup.
public struct FileVault: Sendable {

    /// Category of stored artefact. The raw value is the on-disk subdirectory name.
    public enum Kind: String, Sendable, CaseIterable {
        case pages = "Pages"
        case thumbnails = "Thumbnails"
    }

    public enum VaultError: Error, Equatable, Sendable {
        /// A stored reference escaped the vault root — refused rather than resolved.
        case referenceEscapesVault(String)
        case containerUnavailable
    }

    /// Absolute root of the vault for this app container.
    ///
    /// Absolute paths are **never** persisted: the container UUID changes between
    /// installs and across OS upgrades, so a stored absolute URL silently dangles.
    /// Only paths relative to this root go into the store.
    public let root: URL

    /// A fresh `FileManager` per call. `FileManager.default` is not `Sendable` and
    /// documented as thread-safe only for the default instance's *some* methods; a
    /// per-call instance is cheap and removes the question entirely.
    private var fileManager: FileManager { FileManager() }

    /// The shared vault, rooted at `Application Support/RedactVault`.
    public static let shared: FileVault = {
        // `.applicationSupportDirectory` is guaranteed to resolve on iOS; the
        // fallback keeps the type non-failable without a force-unwrap.
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return FileVault(root: base.appendingPathComponent("RedactVault", isDirectory: true))
    }()

    public init(root: URL) {
        self.root = root
    }

    // MARK: - Layout

    /// Creates the vault directories and applies protection + backup exclusion.
    ///
    /// Idempotent; call once at launch and after any restore.
    public func prepare() throws {
        try createProtectedDirectory(at: root)
        for kind in Kind.allCases {
            try createProtectedDirectory(at: root.appendingPathComponent(kind.rawValue, isDirectory: true))
        }
    }

    private func createProtectedDirectory(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
            )
        }
        // Derived files are reproducible from nothing — there is no source to
        // reproduce them from, but they are also the most sensitive bytes the app
        // holds. Keeping them out of backups means a restored device cannot leak a
        // document the user believed was deleted with the app.
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }

    // MARK: - Writing

    /// Writes `data` into the vault and returns the store-safe **relative** path.
    ///
    /// - Parameters:
    ///   - data: bytes to persist.
    ///   - kind: which subdirectory the artefact belongs to.
    ///   - fileExtension: extension without a leading dot, e.g. `"png"`.
    /// - Returns: a path relative to ``root``, suitable for persisting.
    @discardableResult
    public func write(_ data: Data, kind: Kind, fileExtension: String) throws -> String {
        try prepare()
        let name = "\(UUID().uuidString).\(fileExtension)"
        let relativePath = "\(kind.rawValue)/\(name)"
        let destination = root.appendingPathComponent(relativePath)

        // `.completeFileProtection` would make the file unreadable while the device
        // is locked, which breaks background export. `.completeUnlessOpen` keeps an
        // already-open handle valid across a lock while still encrypting at rest.
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
        return relativePath
    }

    // MARK: - Reading

    /// Resolves a stored relative path against the current container root.
    ///
    /// Throws if the path would escape the vault — a corrupted or hostile reference
    /// must not become a handle to arbitrary app storage.
    public func url(forRelativePath relativePath: String) throws -> URL {
        let resolved = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard resolved.path == rootPath || resolved.path.hasPrefix(rootPath + "/") else {
            throw VaultError.referenceEscapesVault(relativePath)
        }
        return resolved
    }

    public func data(forRelativePath relativePath: String) throws -> Data {
        try Data(contentsOf: url(forRelativePath: relativePath))
    }

    public func fileExists(atRelativePath relativePath: String) -> Bool {
        guard let resolved = try? url(forRelativePath: relativePath) else { return false }
        return fileManager.fileExists(atPath: resolved.path)
    }

    // MARK: - Deleting

    /// Removes a single artefact. Missing files are not an error — delete is
    /// idempotent so a half-completed previous purge can always be finished.
    public func delete(relativePath: String) throws {
        guard let resolved = try? url(forRelativePath: relativePath) else { return }
        guard fileManager.fileExists(atPath: resolved.path) else { return }
        try fileManager.removeItem(at: resolved)
    }

    public func delete(relativePaths: [String]) throws {
        for path in relativePaths {
            try delete(relativePath: path)
        }
    }

    /// Deletes every artefact not referenced by `referencedRelativePaths`.
    ///
    /// A crash between "file written" and "record saved" leaves an orphan. In a
    /// privacy app an orphaned page render is a real leak, so the store sweeps at
    /// launch rather than trusting that no write was ever interrupted.
    /// - Returns: the number of files removed.
    @discardableResult
    public func purgeOrphans(referencedRelativePaths: Set<String>) throws -> Int {
        var removed = 0
        for kind in Kind.allCases {
            let directory = root.appendingPathComponent(kind.rawValue, isDirectory: true)
            guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { continue }
            for name in names {
                let relativePath = "\(kind.rawValue)/\(name)"
                guard !referencedRelativePaths.contains(relativePath) else { continue }
                try fileManager.removeItem(at: directory.appendingPathComponent(name))
                removed += 1
            }
        }
        return removed
    }
}
