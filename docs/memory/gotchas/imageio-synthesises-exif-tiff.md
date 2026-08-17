# ImageIO always writes {Exif} and {TIFF} dictionaries

Verified on the iOS 17 simulator SDK, 2026-08-17.

`CGImageDestination` synthesises metadata containers from the pixels regardless of
what properties you pass:

- `{Exif}` -> `PixelXDimension`, `PixelYDimension` (always, even with empty properties)
- `{TIFF}` -> `Orientation` (whenever `kCGImagePropertyOrientation` is supplied)
- `{JFIF}` (jpeg) / `{PNG}` (png) -> encoder defaults

No source metadata survives — `MetadataStripper.encode` only ever receives a `CGImage`
plus an orientation tag. So a *dictionary-name* assertion
(`metadataDictionaryNames(in:).intersection(["{Exif}","{TIFF}",...]).isEmpty`) can never
pass, and does not measure a leak.

Consequence: `IrreversibilityTests.testMetadataIsStrippedFromRedactedImage` and
`testStandaloneMetadataStripRemovesEXIFAndGPS` fail as written. The correct fix is in the
test, not the stripper: assert on *keys* (no `GPS*`, no `DateTimeOriginal`, no `Make`/`Model`,
no `{IPTC}`/`{XMP}`/`{Photoshop}`/`MakerNote`), or allow `{Exif}`/`{TIFF}` when their contents
are only the synthesised dimension/orientation keys. The integrator did not change the tests.

## Resolved 2026-08-17 (fixer)

Fixed where the gotcha said it belonged: in the assertion, not the stripper. `MetadataStripper`
gained `identifyingMetadataKeys(in:)`, which reports offending **keys** as `"{Dict}/Key"` rather
than container names. `{GPS}`, `{ExifAux}`, `{IPTC}`, `{XMP}`, `{Photoshop}`, `{MakerApple}` are
forbidden outright; `{Exif}` and `{TIFF}` are allowed only for the keys ImageIO synthesises from
the pixel buffer (ColorSpace, PixelXDimension, PixelYDimension / Orientation, resolution,
photometric interpretation, compression). Any other key in them is a leak.

`metadataDictionaryNames(in:)` is retained — the fixture *control* still uses it to prove the
source really carried `{Exif}` and `{GPS}` before the strip.

Both tests are green: 79 executed, 0 failures.
