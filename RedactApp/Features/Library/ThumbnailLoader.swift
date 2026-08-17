import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Decodes and caches vault artefacts at display size.
///
/// The performance rule for this screen is simple and unforgiving: **a list row must
/// never decode a full-resolution page.** A redacted A4 render is 1–4 MB on disk and
/// tens of megabytes decoded; doing that inside a scrolling row drops frames on the
/// first flick and evicts the whole row cache on the second.
///
/// Two things prevent it here:
///
/// 1. `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`
///    decodes **to** the requested size. The full-size bitmap is never materialised,
///    so the cost is bounded by the thumbnail, not by the page.
/// 2. Every decode happens exactly once per key and is then held in an `NSCache`,
///    which evicts under memory pressure on its own.
///
/// Documents saved by the export path already carry a `thumbnailPath` written at save
/// time, so the normal case is a small file read. The first-page fallback exists only
/// for records whose thumbnail is missing, and it is downsampled and cached the same
/// way — it is a one-time cost per document, not a per-scroll one.
@MainActor
public final class ThumbnailLoader {

    /// Shared instance. One cache for the whole app, so pushing into the detail
    /// screen and coming back does not re-decode the row that was just visible.
    public static let shared = ThumbnailLoader()

    private let vault: FileVault
    private let cache = NSCache<NSString, UIImage>()

    /// De-duplicates concurrent requests for the same key: a fast scroll can ask for
    /// the same row three times before the first decode finishes.
    ///
    /// The task yields `Data`, not `UIImage`. `Data` is unambiguously `Sendable`;
    /// leaning on `UIImage`'s sendability to cross an actor boundary is the kind of
    /// assumption that turns into an `@unchecked Sendable` later (`CLAUDE.md` rule 5).
    /// A JPEG round-trip at thumbnail size is sub-millisecond.
    private var inFlight: [String: Task<Data?, Never>] = [:]

    public init(vault: FileVault = .shared, countLimit: Int = 240) {
        self.vault = vault
        cache.countLimit = countLimit
    }

    /// A cached image, if one is already resident. Lets a row draw synchronously on
    /// re-appearance instead of flashing its fallback for a frame.
    public func cachedImage(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    /// Loads `relativePath` from the vault, downsampled so its longest edge is at
    /// most `maxPixel`, and caches the result under `key`.
    ///
    /// Returns `nil` when the file is missing or undecodable — a deleted or corrupt
    /// artefact must degrade to the fallback glyph, never to a crash.
    public func image(forKey key: String, relativePath: String, maxPixel: CGFloat) async -> UIImage? {
        if let hit = cache.object(forKey: key as NSString) { return hit }

        let task: Task<Data?, Never>
        if let existing = inFlight[key] {
            task = existing
        } else {
            let vault = self.vault
            task = Task.detached(priority: .userInitiated) {
                guard let source = try? vault.data(forRelativePath: relativePath) else { return nil }
                return Self.downsampledJPEG(from: source, maxPixel: maxPixel)
            }
            inFlight[key] = task
        }

        let data = await task.value
        inFlight[key] = nil

        guard let data, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    /// Empties the cache after a delete.
    ///
    /// A cached image outlives the file it was decoded from, so a stale entry would
    /// keep showing a page whose bytes are gone — in a privacy app, exactly the wrong
    /// impression. `NSCache` cannot be enumerated, so the whole cache goes; the
    /// remaining rows re-decode at thumbnail size, which is the size the cache is
    /// built for, and deleting is not a hot path.
    public func evictAll() {
        cache.removeAllObjects()
    }

    // MARK: - Decoding

    /// Decodes `data` straight to a bitmap no larger than `maxPixel` on its longest
    /// edge and re-encodes it as JPEG.
    ///
    /// `nonisolated` and `static` so it can run on a detached task without capturing
    /// the loader — nothing here touches actor state.
    nonisolated private static func downsampledJPEG(from data: Data, maxPixel: CGFloat) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Honours the EXIF orientation of the source. Without it a page scanned
            // in landscape lands on its side in the list but upright in the preview.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }

        CGImageDestinationAddImage(
            destination,
            scaled,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

// MARK: - View

/// A vault-backed image that loads at display size and falls back to a glyph.
///
/// The fallback is not a placeholder in the `CLAUDE.md` rule 10 sense — it is the
/// real, final appearance of a document whose render cannot be read. It carries no
/// "loading…" copy and no dead affordance.
struct VaultImage: View {

    /// Cache identity. Must change whenever the underlying bytes could differ.
    let key: String
    /// Vault-relative path, or `nil` when the document has no artefact to show.
    let relativePath: String?
    let maxPixel: CGFloat
    /// SF Symbol shown when there is nothing to draw.
    let fallbackSymbol: String
    /// When non-nil the image becomes a labelled VoiceOver element. Left `nil` (the
    /// default) it is hidden, which is correct for a row thumbnail sitting beside a
    /// label that already says what the document is.
    var accessibilityLabelText: String?

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Token.BG.raised)
                    .overlay(
                        Image(systemName: fallbackSymbol)
                            .foregroundStyle(Token.Text.faint)
                    )
            }
        }
        .modifier(VaultImageAccessibility(label: accessibilityLabelText))
        .accessibleAnimation(Motion.snappy, value: image != nil)
        .task(id: taskIdentity) {
            guard let relativePath else { return }
            if let hit = ThumbnailLoader.shared.cachedImage(forKey: key) {
                image = hit
                return
            }
            image = await ThumbnailLoader.shared.image(
                forKey: key, relativePath: relativePath, maxPixel: maxPixel
            )
        }
    }

    /// Re-runs the load when either the identity or the source path changes. Without
    /// the path in the identity, a row reused for a different document keeps the old
    /// picture — which in a privacy app shows one document's page under another's title.
    private var taskIdentity: String { "\(key)|\(relativePath ?? "")" }
}

/// Labels the image, or hides it when it is decoration beside real text.
private struct VaultImageAccessibility: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isImage)
        } else {
            content.accessibilityHidden(true)
        }
    }
}
