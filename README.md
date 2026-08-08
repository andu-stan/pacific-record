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
  layer implementing [`docs/design-system.md`](docs/design-system.md) — one
  indigo primary with tints for hierarchy, surfaces stepped
  canvas → surface → surface-2 → surface-3 (inverting between themes),
  6pt containers and fully round controls, and an overline/body/caption type
  scale capped at semibold. Screens: the Library
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
  - **Polish (M4)** — app icon (a vinyl record in the brand indigo), VoiceOver
    labels on icon-only controls (covers marked decorative), haptics on scan /
    save, and friendlier Discogs rate-limit / auth messages. Full Dynamic Type
    scaling is the remaining accessibility item (deferred to keep the tuned
    type scale intact).
  - **Estimated value from Discogs** — the detail screen fetches a record's
    market value (a price suggestion for its media condition when a token is
    set, otherwise the lowest current listing) and lets you refresh it. Stored
    on the record (schema v2); the Library header shows the collection total.
    The value is fetched **automatically once both media and sleeve are
    graded** (and re-fetched after a re-grade, since the price is
    condition-specific). Settings holds a **currency** preference and an
    **Update all values** run — paced by a single rate-limited client, shown as
    an inline progress bar, cancellable, and it keeps going if you leave the
    Settings sheet.
  - **High-res cover art** — since Discogs images are user-uploaded scans,
    imports resolve covers through **Apple Music → Deezer → Cover Art Archive →
    Discogs**, stopping at the first that has an image. Settings lets you pick
    the preferred source, or turn on **"Choose cover when adding"** to hand-pick
    from every found cover during import.
    Results are accepted only on a genuine **title** match (fuzzy, ignoring
    edition tags like "(Remastered)"/"(Super Deluxe)" and punctuation) — a
    matching artist alone is never enough, which is what used to return a
    different album by the same act. The new/edit form's **"Choose cover art"** control
    opens the same picker grid on demand, so you can pick a cover for a manual
    entry or swap one later. The grid includes **every image from the Discogs
    release** (front, back, labels…), not just the primary — so a poor scan isn't
    your only Discogs option.
  - **Locations** — track where a split collection physically lives (schema v3).
    Settings › Collection › Locations manages the list (add / rename / delete,
    set a default); the add/edit form has a location picker that preselects the
    default and can create a new location inline; the detail screen shows it.
    Deleting a location unassigns its records rather than deleting them.
  - **Widgets** — two home-screen widgets (small and medium): **Record of the
    Day**, which surfaces a different record from the collection each day and
    opens it when tapped, and **Library Stats** (records / artists / genres and
    the estimated total). A widget can't reach the app's database, so the app
    writes a small JSON snapshot plus downsampled covers into a shared App
    Group container whenever the library changes; the widget only reads that.
    The daily pick is derived from the date rather than stored, so a week of
    timeline entries rotates without the app running.
    Requires the **App Groups** capability on both targets
    (`group.ro.sofistic.pacificrecord`).
  - **Export & share** — Settings › Storage › **Export library** produces
    either a **.zip** (database + every cover — a complete backup) or the
    **.sqlite** database on its own, and hands it to the standard iOS share
    sheet (Files, AirDrop, Mail…). The snapshot uses SQLite's `VACUUM INTO`, so
    it's a consistent, compacted copy of the live database rather than a raw
    file copy.
  - **Import a backup** — Settings › Storage › **Import backup** restores a
    `.zip` or `.sqlite`. The file is unpacked and inspected first, so you see
    what's in it (records, locations, covers) before anything is written, then
    choose **Merge** (add what's missing, keep what you have) or **Replace**
    (wipe and restore, behind a second confirmation). The restore runs at the
    data level — the backup is opened as a second store and copied through the
    normal API — so the live database is never swapped underneath an open
    connection, and an older backup is migrated to the current schema on the
    way in. Reading the zip uses a small built-in extractor over the system
    Compression framework (Foundation can write zips but not read them).
  - **Filter & bulk actions** — the Library's **Filter** control narrows the
    list by location (incl. *Unassigned*), genre, format, media condition,
    minimum rating, and **Discogs sync status** (*Synced* / *Not synced*); the
    count, value total, and search all reflect the filter.
    A **Select** mode turns rows/tiles into a multi-select with a bottom action
    bar to **reassign the location** of, or **delete**, many records at once
    (batched in a single transaction), plus Select-All over the filtered set.
  - **Discogs collection import** — pull an entire Discogs collection into the
    library in one go (empty-state button, or the Add menu → *Import Discogs
    collection*). It resolves the username from the token, pages through the
    collection, and imports each release — metadata, cover art, your Discogs
    rating, and media/sleeve grades when set as Discogs custom fields — while
    **skipping releases already saved**, so it doubles as a re-sync. Progress
    is shown live and the import can be stopped mid-run.
  - **Sync back to Discogs** — records added in the app can be pushed to the
    user's Discogs collection (only ones linked to a Discogs release — scanned
    or searched, not manual entries). Two ways, both opt-in and de-duplicated:
    a Settings toggle to add every new record automatically, and an **Add to
    Discogs collection** button on the record detail screen. It checks the
    collection first to avoid duplicate instances and also pushes the star
    rating. Backed by write endpoints on `DiscogsClient` (the HTTP seam gained
    POST support). Each record remembers when it was last confirmed in the
    collection (`discogs_synced_at`, schema v4) — set on import and on a
    successful push — which drives the *Synced / Not synced* filter above.

See the roadmap in [`docs/PLAN.md`](docs/PLAN.md).

> **Build note:** iOS apps compile with Xcode on macOS. The plan splits the
> code into a portable **VinylCore** Swift package (models, database, metadata
> clients — buildable/testable on Linux) and the **iOS app** (SwiftUI,
> VisionKit, iCloud — built in Xcode).
