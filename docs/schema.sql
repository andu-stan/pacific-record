-- =============================================================================
-- Pacific Record — vinyl library schema (SQLite)  ·  v1 "Collector set"
-- =============================================================================
-- Design goals:
--   * Plain SQLite so other applications can open and read the library.
--   * Stable UUID primary keys (safe across merges / exports).
--   * Cover images are stored as FILES in the library's Covers/ folder, not as
--     blobs, so iCloud can sync them incrementally and other apps can view them.
--     The DB only stores relative paths.
--   * ISO-8601 text timestamps (portable, human-readable).
--
-- Migrations are applied by the app (GRDB DatabaseMigrator). `library_meta`
-- records the schema version for external readers.
-- =============================================================================

PRAGMA foreign_keys = ON;

-- Library-level metadata, for external readers and migration checks.
CREATE TABLE library_meta (
    key   TEXT PRIMARY KEY,
    value TEXT
);
-- Seeded with e.g. ('schema_version','1'), ('generator','Pacific Record 1.0').

-- -----------------------------------------------------------------------------
-- The record (a specific pressing/release).
-- -----------------------------------------------------------------------------
CREATE TABLE release (
    id                 TEXT PRIMARY KEY,        -- UUID string
    title              TEXT NOT NULL,
    artist_display     TEXT NOT NULL,           -- denormalized, for fast lists ("Miles Davis")
    year               INTEGER,                 -- pressing/release year
    country            TEXT,
    genre              TEXT,                    -- primary genre
    styles             TEXT,                    -- JSON array of sub-styles, e.g. ["Hard Bop"]
    format             TEXT,                    -- LP, EP, 7", 10", 12", Box, ...
    speed              TEXT,                    -- "33 1/3", "45", "78"
    disc_count         INTEGER DEFAULT 1,
    barcode            TEXT,                    -- UPC/EAN as scanned
    discogs_release_id INTEGER,                 -- provenance (nullable)
    musicbrainz_mbid   TEXT,                    -- provenance (nullable)
    cover_path         TEXT,                    -- relative path, e.g. "Covers/<id>.jpg"
    thumb_path         TEXT,                    -- relative path to generated thumbnail
    media_condition    TEXT,                    -- Goldmine: M, NM, VG+, VG, G+, G, F, P
    sleeve_condition   TEXT,                    -- Goldmine scale (same values)
    rating             INTEGER DEFAULT 0,       -- 0..5
    notes              TEXT,
    added_at           TEXT NOT NULL,           -- ISO-8601
    updated_at         TEXT NOT NULL            -- ISO-8601
);

-- -----------------------------------------------------------------------------
-- Artists (normalized) + many-to-many join. artist_display on `release` keeps
-- list rendering cheap; this gives correct "all records by artist X" queries.
-- -----------------------------------------------------------------------------
CREATE TABLE artist (
    id        TEXT PRIMARY KEY,                 -- UUID string
    name      TEXT NOT NULL,
    sort_name TEXT                              -- "Davis, Miles"
);

CREATE TABLE release_artist (
    release_id TEXT NOT NULL REFERENCES release(id) ON DELETE CASCADE,
    artist_id  TEXT NOT NULL REFERENCES artist(id)  ON DELETE CASCADE,
    role       TEXT,                            -- "Main", "Featuring", "Producer", ...
    position   INTEGER DEFAULT 0,               -- ordering of credits
    PRIMARY KEY (release_id, artist_id, role)
);

-- -----------------------------------------------------------------------------
-- Labels + join (a release can carry multiple labels / catalogue numbers).
-- -----------------------------------------------------------------------------
CREATE TABLE label (
    id   TEXT PRIMARY KEY,                      -- UUID string
    name TEXT NOT NULL
);

CREATE TABLE release_label (
    release_id     TEXT NOT NULL REFERENCES release(id) ON DELETE CASCADE,
    label_id       TEXT NOT NULL REFERENCES label(id)   ON DELETE CASCADE,
    catalog_number TEXT,
    PRIMARY KEY (release_id, label_id, catalog_number)
);

-- -----------------------------------------------------------------------------
-- Tracklist (populated from online lookup; optional for manual entries).
-- -----------------------------------------------------------------------------
CREATE TABLE track (
    id               TEXT PRIMARY KEY,          -- UUID string
    release_id       TEXT NOT NULL REFERENCES release(id) ON DELETE CASCADE,
    position         TEXT,                      -- "A1", "B2", "1", ...
    side             TEXT,                      -- "A", "B", ...
    title            TEXT NOT NULL,
    duration_seconds INTEGER,
    track_index      INTEGER DEFAULT 0          -- explicit ordering
);

-- -----------------------------------------------------------------------------
-- Indexes for the common sort/filter/lookup paths.
-- -----------------------------------------------------------------------------
CREATE INDEX idx_release_artist_display ON release(artist_display);
CREATE INDEX idx_release_title          ON release(title);
CREATE INDEX idx_release_year           ON release(year);
CREATE INDEX idx_release_barcode        ON release(barcode);
CREATE INDEX idx_ra_release             ON release_artist(release_id);
CREATE INDEX idx_rl_release             ON release_label(release_id);
CREATE INDEX idx_track_release          ON track(release_id);

-- -----------------------------------------------------------------------------
-- Full-text search over the fields people actually search by.
-- Maintained by the app (LibraryStore) on each write: the rowid maps to the
-- release via `release_uuid`. Kept simple and self-contained on purpose.
-- -----------------------------------------------------------------------------
CREATE VIRTUAL TABLE release_fts USING fts5(
    release_uuid UNINDEXED,
    title,
    artist_display,
    label,
    catalog_number,
    notes
);
