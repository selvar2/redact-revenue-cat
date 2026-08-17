import CoreGraphics
import Foundation

/// Layout constants that belong to the library feature specifically.
///
/// `CLAUDE.md` rule 3 says no view spells out a bare number. Everything that has a
/// design token — colour, type, radius, spacing, shadow, animation — comes from
/// `DesignSystem/`. What is left are three measurements the token file has no entry
/// for (thumbnail box geometry, decode budgets) and one duration. They are named
/// here, once, rather than scattered through the views.
///
/// `DesignSystem/**` is the `design-system` agent's allowlist, so this file cannot
/// add them to `Token`. See `docs/memory/gotchas/library-layout-constants-not-tokens.md`
/// — these are candidates for promotion into `Token.Size` when that scope reopens.
enum LibraryLayout {

    /// ISO 216 page proportion (1 : √2). The thumbnail box matches the shape of the
    /// page it shows, so a portrait scan is letterboxed by nothing.
    static let pageAspectRatio: CGFloat = 1 / 1.414_213_6

    /// Row thumbnail width — 1.5× the icon well it stands in for, so a row with a
    /// render and a row with a fallback glyph have a comparable visual mass.
    static let rowThumbnailWidth = Token.Size.iconWell * 1.5

    static let rowThumbnailHeight = rowThumbnailWidth / pageAspectRatio

    /// Longest edge, in pixels, requested from ImageIO for a row thumbnail.
    ///
    /// This is the number that makes the list scroll. ImageIO decodes *to* this size
    /// rather than decoding the full page and shrinking it, so a 4000px A4 render
    /// never enters memory at full size. 240 covers ``rowThumbnailWidth`` at 3×.
    static let rowThumbnailPixels: CGFloat = 240

    /// Longest edge for the detail screen's full-size preview. Above roughly this,
    /// extra pixels cost memory on every device and are visible on none.
    static let detailPreviewPixels: CGFloat = 2048

    /// How long a deleted document can be brought back.
    ///
    /// Long enough to read the snackbar and react, short enough that the user is not
    /// left wondering whether the delete happened. The files are still on disk for
    /// this window and nowhere else — see ``LibraryModel``.
    static let undoWindow: TimeInterval = 5
}
