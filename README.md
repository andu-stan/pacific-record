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

## Status

Planning. No app code yet. See the roadmap in [`docs/PLAN.md`](docs/PLAN.md).

> **Build note:** iOS apps compile with Xcode on macOS. The plan splits the
> code into a portable **VinylCore** Swift package (models, database, metadata
> clients — buildable/testable on Linux) and the **iOS app** (SwiftUI,
> VisionKit, iCloud — built in Xcode).
