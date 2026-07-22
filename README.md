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

### iCloud signing

The app declares an iCloud Documents container (`iCloud.com.pacificrecord.app`)
so the library appears in the Files app and syncs across devices. Building with
this requires a **paid Apple Developer account**: open the project, select your
Team under Signing & Capabilities, and let automatic signing provision the
container (rename the bundle id + container id to your own if needed — they must
match). On a **free** account, remove `CODE_SIGN_ENTITLEMENTS` and the
`NSUbiquitousContainers` key — the app then runs entirely on-device (it already
falls back to local storage at runtime whenever iCloud is unavailable).

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
    location (never deletes).

See the roadmap in [`docs/PLAN.md`](docs/PLAN.md).

> **Build note:** iOS apps compile with Xcode on macOS. The plan splits the
> code into a portable **VinylCore** Swift package (models, database, metadata
> clients — buildable/testable on Linux) and the **iOS app** (SwiftUI,
> VisionKit, iCloud — built in Xcode).
