# Pacific Record

An iOS app for cataloguing a vinyl records library. The library is stored as a
plain, portable **SQLite database + cover-art folder in iCloud Drive**, so it
can be opened and read by other applications — not locked inside the app.

## What it does

- Browse the whole collection as a cover-art grid or a detailed list, with
  search, sort, and filtering.
- Add records three ways:
  - **Scan a barcode** → look the release up online → auto-fill details and
    download the highest-resolution cover art available.
  - **Search by text** (artist / title) when there's no barcode.
  - **Enter everything manually.**
- Track collector details per record: label, catalogue number, pressing year,
  country, genre/styles, format & speed, media + sleeve condition (Goldmine
  grading), personal rating, and free-text notes.
- Track a collection split across **multiple locations** (a shelf, a room, even
  another country): manage the list, set a default, and pick a location when
  adding a record. The default is preselected automatically.

## Key decisions

| Area | Choice |
| --- | --- |
| Platform | iOS 17+, SwiftUI (iPhone-first, iPad-compatible) |
| Storage | iCloud Drive — single SQLite file + `Covers/` folder, Files-visible |
| Database | SQLite via GRDB.swift (documented schema, external-app readable) |
| Metadata | Discogs (primary) + MusicBrainz / Cover Art Archive (fallback) |
| Barcode | VisionKit `DataScannerViewController` |
| Distribution | Personal — sideload or TestFlight, user-supplied Discogs token |

## Documentation

- [`docs/PLAN.md`](docs/PLAN.md) — full development plan: architecture,
  storage design, metadata pipeline, screens, milestones, risks.
- [`docs/schema.sql`](docs/schema.sql) — the SQLite schema, annotated.
- [`docs/design/`](docs/design) — the source design (Claude Design export)
  the UI is built from.
- [`VinylCore/`](VinylCore) — the portable, UI-free core (models, database,
  metadata clients) as a Swift package with tests.
- [`PacificRecord/`](PacificRecord) — the SwiftUI iOS app.

## Building

The app is generated from [`project.yml`](project.yml) with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen      # one-time
xcodegen generate          # writes PacificRecord.xcodeproj
open PacificRecord.xcodeproj
```

To build/verify just the core from the command line: `cd VinylCore && swift test`.

### iCloud (currently disabled)

iCloud Drive storage is **off by default** so the app builds and runs on a
**free** Apple ID: `AppConfig.iCloudEnabled = false`, and the entitlement and
container declaration are commented out (`project.yml`, `Info.plist`). The app
runs entirely on-device.

To enable it once you have a **paid Apple Developer** team:

1. Set `AppConfig.iCloudEnabled = true` (`PacificRecord/Sources/App/AppConfig.swift`).
2. Uncomment `CODE_SIGN_ENTITLEMENTS` in `project.yml`.
3. Uncomment `NSUbiquitousContainers` in `PacificRecord/Info.plist`.
4. Run `xcodegen generate`, then select your Team under Signing & Capabilities
   (rename the bundle id + `iCloud.…` container id to your own if needed — they
   must match).

## Status

- **`VinylCore`** — data models, the GRDB-backed `LibraryStore` (schema, CRUD,
  full-text search), the Discogs/MusicBrainz metadata clients, and unit tests.
- **`PacificRecord`** — the SwiftUI app implementing the design: a design-system
  layer (SF Pro type scale + adaptive light/dark palette), the Library
  (grid / list / empty), Record detail, the add flow, Settings, and first-run
  onboarding. Fonts are **SF Pro only** (the system font); icons use SF Symbols.
  - **Live barcode scanning** via VisionKit `DataScannerViewController` (with a
    type-a-barcode fallback in the Simulator, which has no camera).
  - **Real metadata lookups** — barcode/text searches hit Discogs (using the
    token from Settings) with MusicBrainz as fallback; the chosen pressing is
    enriched, its cover downloaded to the library folder, and the form is
    prefilled for you to add condition/rating before saving.
  - The library **starts empty** — no seeded sample data.
  - **iCloud Drive storage** — the SQLite file + `Covers/` folder live in the
    app's iCloud container (visible in Files, readable by other apps), resolved
    asynchronously at launch with a graceful **local fallback** when iCloud is
    off. Switchable from Settings; switching copies your library to the new
    location (never deletes). *Currently disabled by default* so the app builds
    on a free account — see [iCloud](#icloud-currently-disabled) to enable.
  - **Polish (M4)** — app icon (a vinyl record in the brand amber), VoiceOver
    labels on icon-only controls (covers marked decorative), haptics on scan /
    save, and friendlier Discogs rate-limit / auth messages. Full Dynamic Type
    scaling is the remaining accessibility item (deferred to keep the tuned
    type scale intact).
  - **Estimated value from Discogs** — the detail screen fetches a record's
    market value (a price suggestion for its media condition when a token is
    set, otherwise the lowest current listing) and lets you refresh it. Stored
    on the record (schema v2); the Library header shows the collection total.
  - **High-res cover art** — since Discogs images are user-uploaded scans,
    imports resolve covers through **Apple Music → Cover Art Archive → Discogs**,
    stopping at the first that has an image. Settings lets you pick the preferred
    source, or turn on **"Choose cover when adding"** to hand-pick from every
    found cover during import. The new/edit form's **"Choose cover art"** control
    opens the same picker grid on demand, so you can pick a cover for a manual
    entry or swap one later. The grid includes **every image from the Discogs
    release** (front, back, labels…), not just the primary — so a poor scan isn't
    your only Discogs option.
  - **Locations** — track where a split collection physically lives (schema v3).
    Settings › Collection › Locations manages the list (add / rename / delete,
    set a default); the add/edit form has a location picker that preselects the
    default and can create a new location inline; the detail screen shows it.
    Deleting a location unassigns its records rather than deleting them.
  - **Filter & bulk actions** — the Library's **Filter** control narrows the
    list by location (incl. *Unassigned*), genre, format, media condition, and
    minimum rating; the count, value total, and search all reflect the filter.
    A **Select** mode turns rows/tiles into a multi-select with a bottom action
    bar to **reassign the location** of, or **delete**, many records at once
    (batched in a single transaction), plus Select-All over the filtered set.

See the roadmap in [`docs/PLAN.md`](docs/PLAN.md).

> **Build note:** iOS apps compile with Xcode on macOS. The plan splits the
> code into a portable **VinylCore** Swift package (models, database, metadata
> clients — buildable/testable on Linux) and the **iOS app** (SwiftUI,
> VisionKit, iCloud — built in Xcode).
