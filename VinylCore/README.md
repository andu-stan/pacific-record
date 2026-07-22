# VinylCore

The portable, UI-free core of **Pacific Record**: data models, the SQLite
database layer, and the Discogs / MusicBrainz metadata clients. The iOS app
(SwiftUI, VisionKit barcode scanner, iCloud file coordination) is a separate
Xcode target that depends on this package.

Keeping this logic in a plain Swift package means it can be built and
**unit-tested from the command line** — no simulator required:

```sh
cd VinylCore
swift test
```

> Requires a Swift 5.9+ toolchain. On macOS this comes with Xcode. On Linux the
> package also builds (it links the system `libsqlite3`), but the barcode
> scanner and iCloud sync are iOS-only and live in the app target, not here.

## What's inside

| Area | Files | Notes |
| --- | --- | --- |
| Models | `Sources/VinylCore/Models/` | `Release`, `Artist`, `Label`, `Track`, `Condition` (Goldmine), plus `RecordDetail` / `LabelCredit` aggregates. GRDB records with `CodingKeys` mapped to the snake_case schema. |
| Database | `Sources/VinylCore/Database/LibraryStore.swift` | GRDB `DatabaseQueue`, migrations, CRUD, FTS5 search. Points at any file path — the app passes the URL inside the iCloud container. |
| Metadata | `Sources/VinylCore/Metadata/` | `DiscogsClient` (primary) + `MusicBrainzClient` (fallback) behind `CompositeMetadataProvider`. All network access goes through the injectable `HTTPClient`, so parsing is tested offline against fixtures. |
| Images | `Sources/VinylCore/Images/CoverImageManager.swift` | Downloads hi-res cover art into the library's `Covers/` folder; generates a thumbnail via ImageIO (Apple platforms). |
| Tests | `Tests/VinylCoreTests/` | Round-trip DB tests, FTS search, Discogs/MusicBrainz parsing against `Fixtures/*.json`, and composite-fallback behaviour. |

## Design notes

- **The database is the interchange format.** The schema (see
  [`../docs/schema.sql`](../docs/schema.sql)) is plain SQLite with stable UUID
  keys, so other apps can open the library directly.
- **Network is a seam.** `HTTPClient` is a one-method protocol; the live
  implementation wraps `URLSession`, and tests inject a stub returning recorded
  JSON. No test hits the network or needs a Discogs token.
- **Two-step lookups.** `searchByBarcode` / `searchByText` return lightweight
  candidate matches (for the "which pressing is this?" picker); `enrich(_:)`
  then fetches the full release (tracklist + highest-resolution cover) for the
  one the user picks.
