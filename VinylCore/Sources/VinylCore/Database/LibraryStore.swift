import Foundation
import GRDB

/// The library repository over a SQLite database. Owns schema migrations, CRUD,
/// and full-text search. It's handed a file path — the app points it at the
/// `library.sqlite` file inside the iCloud container; tests use a temp file.
public final class LibraryStore {
    private let dbQueue: DatabaseQueue

    public enum SortOrder: Sendable, CaseIterable {
        case artist
        case title
        case yearDescending
        case dateAddedDescending
        case ratingDescending
    }

    /// Opens (creating if needed) the database at `path` and runs migrations.
    public init(path: String) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(path: path, configuration: configuration)
        try Self.migrator.migrate(dbQueue)
    }

    // MARK: - Migrations

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "library_meta") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text)
            }

            try db.create(table: "release") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("artist_display", .text).notNull()
                t.column("year", .integer)
                t.column("country", .text)
                t.column("genre", .text)
                t.column("styles", .text)
                t.column("format", .text)
                t.column("speed", .text)
                t.column("disc_count", .integer).notNull().defaults(to: 1)
                t.column("barcode", .text)
                t.column("discogs_release_id", .integer)
                t.column("musicbrainz_mbid", .text)
                t.column("cover_path", .text)
                t.column("thumb_path", .text)
                t.column("media_condition", .text)
                t.column("sleeve_condition", .text)
                t.column("rating", .integer).notNull().defaults(to: 0)
                t.column("notes", .text)
                t.column("added_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "artist") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("sort_name", .text)
            }

            try db.create(table: "release_artist") { t in
                t.column("release_id", .text).notNull()
                    .references("release", onDelete: .cascade)
                t.column("artist_id", .text).notNull()
                    .references("artist", onDelete: .cascade)
                t.column("role", .text).notNull().defaults(to: "Main")
                t.column("position", .integer).notNull().defaults(to: 0)
                t.primaryKey(["release_id", "artist_id", "role"])
            }

            try db.create(table: "label") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
            }

            try db.create(table: "release_label") { t in
                t.column("release_id", .text).notNull()
                    .references("release", onDelete: .cascade)
                t.column("label_id", .text).notNull()
                    .references("label", onDelete: .cascade)
                t.column("catalog_number", .text)
                t.primaryKey(["release_id", "label_id"])
            }

            try db.create(table: "track") { t in
                t.column("id", .text).primaryKey()
                t.column("release_id", .text).notNull()
                    .references("release", onDelete: .cascade)
                t.column("position", .text)
                t.column("side", .text)
                t.column("title", .text).notNull()
                t.column("duration_seconds", .integer)
                t.column("track_index", .integer).notNull().defaults(to: 0)
            }

            try db.create(index: "idx_release_artist_display", on: "release", columns: ["artist_display"])
            try db.create(index: "idx_release_title", on: "release", columns: ["title"])
            try db.create(index: "idx_release_year", on: "release", columns: ["year"])
            try db.create(index: "idx_release_barcode", on: "release", columns: ["barcode"])
            try db.create(index: "idx_ra_release", on: "release_artist", columns: ["release_id"])
            try db.create(index: "idx_rl_release", on: "release_label", columns: ["release_id"])
            try db.create(index: "idx_track_release", on: "track", columns: ["release_id"])

            try db.create(virtualTable: "release_fts", using: FTS5()) { t in
                t.column("release_uuid").notIndexed()
                t.column("title")
                t.column("artist_display")
                t.column("label")
                t.column("catalog_number")
                t.column("notes")
            }

            try db.execute(
                sql: "INSERT INTO library_meta (key, value) VALUES (?, ?), (?, ?)",
                arguments: ["schema_version", "1", "generator", "Pacific Record VinylCore"]
            )
        }

        migrator.registerMigration("v2") { db in
            try db.alter(table: "release") { t in
                t.add(column: "estimated_value", .double)
                t.add(column: "value_currency", .text)
                t.add(column: "value_basis", .text)
                t.add(column: "value_updated_at", .datetime)
            }
            try db.execute(sql: "UPDATE library_meta SET value = ? WHERE key = ?", arguments: ["2", "schema_version"])
        }

        return migrator
    }

    // MARK: - Writing

    /// Inserts or updates a record and its associations atomically, and keeps
    /// the full-text index in sync.
    public func save(_ detail: RecordDetail) throws {
        try dbQueue.write { db in
            var release = detail.release
            release.updatedAt = Date()

            if try Release.fetchOne(db, key: release.id) != nil {
                try release.update(db)
            } else {
                try release.insert(db)
            }

            // Artists (dedup by name, replace this release's credits).
            try db.execute(sql: "DELETE FROM release_artist WHERE release_id = ?", arguments: [release.id])
            for (index, artist) in detail.artists.enumerated() {
                let artistID = try Self.findOrCreateArtist(db, name: artist.name, sortName: artist.sortName)
                try db.execute(
                    sql: "INSERT OR IGNORE INTO release_artist (release_id, artist_id, role, position) VALUES (?, ?, 'Main', ?)",
                    arguments: [release.id, artistID, index]
                )
            }

            // Labels (dedup by name, replace this release's label credits).
            try db.execute(sql: "DELETE FROM release_label WHERE release_id = ?", arguments: [release.id])
            for credit in detail.labels {
                let labelID = try Self.findOrCreateLabel(db, name: credit.name)
                try db.execute(
                    sql: "INSERT OR REPLACE INTO release_label (release_id, label_id, catalog_number) VALUES (?, ?, ?)",
                    arguments: [release.id, labelID, credit.catalogNumber]
                )
            }

            // Tracks (fully replace).
            try db.execute(sql: "DELETE FROM track WHERE release_id = ?", arguments: [release.id])
            for var track in detail.tracks {
                track.releaseID = release.id
                try track.insert(db)
            }

            try Self.rebuildFTS(db, release: release, labels: detail.labels)
        }
    }

    /// Updates just the `release` row (e.g. after editing condition/rating) and
    /// refreshes the searchable fields.
    public func update(_ release: Release) throws {
        try dbQueue.write { db in
            var updated = release
            updated.updatedAt = Date()
            try updated.update(db)
            let labels = try Self.labelCredits(db, releaseID: updated.id)
            try Self.rebuildFTS(db, release: updated, labels: labels)
        }
    }

    public func delete(id: String) throws {
        try dbQueue.write { db in
            // Associations cascade via foreign keys; the FTS row is manual.
            _ = try Release.deleteOne(db, key: id)
            try db.execute(sql: "DELETE FROM release_fts WHERE release_uuid = ?", arguments: [id])
        }
    }

    // MARK: - Reading

    public func allReleases(sortedBy sort: SortOrder = .artist) throws -> [Release] {
        try dbQueue.read { db in
            try Release.fetchAll(db, sql: "SELECT * FROM release ORDER BY \(Self.orderClause(sort))")
        }
    }

    public func count() throws -> Int {
        try dbQueue.read { db in
            try Release.fetchCount(db)
        }
    }

    /// The full record with artists, labels, and tracks, or nil if not found.
    public func detail(id: String) throws -> RecordDetail? {
        try dbQueue.read { db in
            guard let release = try Release.fetchOne(db, key: id) else { return nil }
            let artists = try Artist.fetchAll(db, sql: """
                SELECT artist.* FROM artist
                JOIN release_artist ra ON ra.artist_id = artist.id
                WHERE ra.release_id = ?
                ORDER BY ra.position
                """, arguments: [id])
            let labels = try Self.labelCredits(db, releaseID: id)
            let tracks = try Track.fetchAll(db, sql: """
                SELECT * FROM track WHERE release_id = ? ORDER BY track_index
                """, arguments: [id])
            return RecordDetail(release: release, artists: artists, labels: labels, tracks: tracks)
        }
    }

    /// Full-text search across title, artist, label, catalogue number, and
    /// notes. Empty query returns the whole library. Tokens are matched as
    /// prefixes so search-as-you-type works.
    public func search(_ text: String) throws -> [Release] {
        let tokens = text
            .split(whereSeparator: { $0 == " " || $0.isNewline })
            .map { Self.sanitizeFTSToken(String($0)) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return try allReleases() }

        let matchExpression = tokens.map { "\"\($0)\"*" }.joined(separator: " AND ")
        return try dbQueue.read { db in
            try Release.fetchAll(db, sql: """
                SELECT release.* FROM release
                JOIN release_fts ON release_fts.release_uuid = release.id
                WHERE release_fts MATCH ?
                ORDER BY release_fts.rank
                """, arguments: [matchExpression])
        }
    }

    // MARK: - Helpers

    private static func orderClause(_ sort: SortOrder) -> String {
        switch sort {
        case .artist:
            return "artist_display COLLATE NOCASE ASC, title COLLATE NOCASE ASC"
        case .title:
            return "title COLLATE NOCASE ASC"
        case .yearDescending:
            // "(year IS NULL)" sorts unknown years last, portably.
            return "(year IS NULL) ASC, year DESC, title COLLATE NOCASE ASC"
        case .dateAddedDescending:
            return "added_at DESC"
        case .ratingDescending:
            return "rating DESC, artist_display COLLATE NOCASE ASC"
        }
    }

    private static func findOrCreateArtist(_ db: Database, name: String, sortName: String?) throws -> String {
        if let row = try Row.fetchOne(db, sql: "SELECT id FROM artist WHERE name = ? LIMIT 1", arguments: [name]) {
            let existingID: String = row["id"]
            return existingID
        }
        let id = UUID().uuidString
        try db.execute(
            sql: "INSERT INTO artist (id, name, sort_name) VALUES (?, ?, ?)",
            arguments: [id, name, sortName]
        )
        return id
    }

    private static func findOrCreateLabel(_ db: Database, name: String) throws -> String {
        if let row = try Row.fetchOne(db, sql: "SELECT id FROM label WHERE name = ? LIMIT 1", arguments: [name]) {
            let existingID: String = row["id"]
            return existingID
        }
        let id = UUID().uuidString
        try db.execute(sql: "INSERT INTO label (id, name) VALUES (?, ?)", arguments: [id, name])
        return id
    }

    private static func labelCredits(_ db: Database, releaseID: String) throws -> [LabelCredit] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT label.name AS name, rl.catalog_number AS catno FROM label
            JOIN release_label rl ON rl.label_id = label.id
            WHERE rl.release_id = ?
            """, arguments: [releaseID])
        return rows.map { row in
            let name: String = row["name"]
            let catno: String? = row["catno"]
            return LabelCredit(name: name, catalogNumber: catno)
        }
    }

    private static func rebuildFTS(_ db: Database, release: Release, labels: [LabelCredit]) throws {
        try db.execute(sql: "DELETE FROM release_fts WHERE release_uuid = ?", arguments: [release.id])
        let labelNames = labels.map(\.name).joined(separator: " ")
        let catalogNumbers = labels.compactMap(\.catalogNumber).joined(separator: " ")
        try db.execute(sql: """
            INSERT INTO release_fts (release_uuid, title, artist_display, label, catalog_number, notes)
            VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [
                release.id,
                release.title,
                release.artistDisplay,
                labelNames,
                catalogNumbers,
                release.notes ?? "",
            ])
    }

    /// Keeps only characters safe to drop into an FTS5 quoted token.
    private static func sanitizeFTSToken(_ token: String) -> String {
        var result = ""
        for scalar in token.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            result.unicodeScalars.append(scalar)
        }
        return result
    }
}
