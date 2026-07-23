import Foundation
import GRDB

// MARK: - Release

/// A single record (a specific pressing/release) as stored in the `release`
/// table. `CodingKeys` map Swift camelCase to the snake_case columns.
public struct Release: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    /// Denormalized artist string for fast list rendering (e.g. "Miles Davis").
    public var artistDisplay: String
    public var year: Int?
    public var country: String?
    public var genre: String?
    /// Sub-styles; stored as JSON text by GRDB.
    public var styles: [String]
    public var format: String?
    public var speed: String?
    public var discCount: Int
    public var barcode: String?
    public var discogsReleaseID: Int?
    public var musicbrainzMBID: String?
    /// Relative path inside the library folder, e.g. "Covers/<id>.jpg".
    public var coverPath: String?
    public var thumbPath: String?
    public var mediaCondition: Condition?
    public var sleeveCondition: Condition?
    public var rating: Int
    public var notes: String?
    public var addedAt: Date
    public var updatedAt: Date
    /// Estimated market value (from Discogs), if fetched.
    public var estimatedValue: Double?
    public var valueCurrency: String?
    /// What the value is based on: a Goldmine grade ("NM") or "Lowest listing".
    public var valueBasis: String?
    public var valueUpdatedAt: Date?
    /// The location (shelf/room/country/…) this record is stored at.
    public var locationID: String?

    public static let databaseTableName = "release"

    public enum CodingKeys: String, CodingKey {
        case id
        case title
        case artistDisplay = "artist_display"
        case year
        case country
        case genre
        case styles
        case format
        case speed
        case discCount = "disc_count"
        case barcode
        case discogsReleaseID = "discogs_release_id"
        case musicbrainzMBID = "musicbrainz_mbid"
        case coverPath = "cover_path"
        case thumbPath = "thumb_path"
        case mediaCondition = "media_condition"
        case sleeveCondition = "sleeve_condition"
        case rating
        case notes
        case addedAt = "added_at"
        case updatedAt = "updated_at"
        case estimatedValue = "estimated_value"
        case valueCurrency = "value_currency"
        case valueBasis = "value_basis"
        case valueUpdatedAt = "value_updated_at"
        case locationID = "location_id"
    }

    public init(
        id: String,
        title: String,
        artistDisplay: String,
        year: Int? = nil,
        country: String? = nil,
        genre: String? = nil,
        styles: [String] = [],
        format: String? = nil,
        speed: String? = nil,
        discCount: Int = 1,
        barcode: String? = nil,
        discogsReleaseID: Int? = nil,
        musicbrainzMBID: String? = nil,
        coverPath: String? = nil,
        thumbPath: String? = nil,
        mediaCondition: Condition? = nil,
        sleeveCondition: Condition? = nil,
        rating: Int = 0,
        notes: String? = nil,
        addedAt: Date = Date(),
        updatedAt: Date = Date(),
        estimatedValue: Double? = nil,
        valueCurrency: String? = nil,
        valueBasis: String? = nil,
        valueUpdatedAt: Date? = nil,
        locationID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artistDisplay = artistDisplay
        self.year = year
        self.country = country
        self.genre = genre
        self.styles = styles
        self.format = format
        self.speed = speed
        self.discCount = discCount
        self.barcode = barcode
        self.discogsReleaseID = discogsReleaseID
        self.musicbrainzMBID = musicbrainzMBID
        self.coverPath = coverPath
        self.thumbPath = thumbPath
        self.mediaCondition = mediaCondition
        self.sleeveCondition = sleeveCondition
        self.rating = rating
        self.notes = notes
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.estimatedValue = estimatedValue
        self.valueCurrency = valueCurrency
        self.valueBasis = valueBasis
        self.valueUpdatedAt = valueUpdatedAt
        self.locationID = locationID
    }
}

// MARK: - Artist

public struct Artist: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var sortName: String?

    public static let databaseTableName = "artist"

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case sortName = "sort_name"
    }

    public init(id: String, name: String, sortName: String? = nil) {
        self.id = id
        self.name = name
        self.sortName = sortName
    }
}

// MARK: - Label

public struct Label: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String

    public static let databaseTableName = "label"

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Track

public struct Track: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public var id: String
    public var releaseID: String
    public var position: String?
    public var side: String?
    public var title: String
    public var durationSeconds: Int?
    public var trackIndex: Int

    public static let databaseTableName = "track"

    public enum CodingKeys: String, CodingKey {
        case id
        case releaseID = "release_id"
        case position
        case side
        case title
        case durationSeconds = "duration_seconds"
        case trackIndex = "track_index"
    }

    public init(
        id: String,
        releaseID: String,
        position: String? = nil,
        side: String? = nil,
        title: String,
        durationSeconds: Int? = nil,
        trackIndex: Int = 0
    ) {
        self.id = id
        self.releaseID = releaseID
        self.position = position
        self.side = side
        self.title = title
        self.durationSeconds = durationSeconds
        self.trackIndex = trackIndex
    }
}

// MARK: - Aggregates

/// A label credit as it appears on a release: the label name plus the
/// catalogue number printed for that label.
public struct LabelCredit: Sendable, Equatable {
    public var name: String
    public var catalogNumber: String?

    public init(name: String, catalogNumber: String? = nil) {
        self.name = name
        self.catalogNumber = catalogNumber
    }
}

/// A record together with its related artists, labels, and tracks — the shape
/// the detail screen shows and the store saves atomically.
public struct RecordDetail: Sendable, Equatable {
    public var release: Release
    public var artists: [Artist]
    public var labels: [LabelCredit]
    public var tracks: [Track]

    public init(release: Release, artists: [Artist] = [], labels: [LabelCredit] = [], tracks: [Track] = []) {
        self.release = release
        self.artists = artists
        self.labels = labels
        self.tracks = tracks
    }
}

public extension RecordDetail {
    /// Builds a savable draft from an online metadata match, assigning fresh
    /// UUIDs and letting the caller supply the collector fields (condition,
    /// rating, notes) and downloaded cover paths.
    static func draft(
        from match: MetadataMatch,
        id: String = UUID().uuidString,
        coverPath: String? = nil,
        thumbPath: String? = nil,
        mediaCondition: Condition? = nil,
        sleeveCondition: Condition? = nil,
        rating: Int = 0,
        notes: String? = nil,
        now: Date = Date()
    ) -> RecordDetail {
        let release = Release(
            id: id,
            title: match.title,
            artistDisplay: match.artistDisplay,
            year: match.year,
            country: match.country,
            genre: match.genre,
            styles: match.styles,
            format: match.format,
            speed: match.speed,
            discCount: 1,
            barcode: match.barcode,
            discogsReleaseID: match.discogsReleaseID,
            musicbrainzMBID: match.musicbrainzMBID,
            coverPath: coverPath,
            thumbPath: thumbPath,
            mediaCondition: mediaCondition,
            sleeveCondition: sleeveCondition,
            rating: rating,
            notes: notes,
            addedAt: now,
            updatedAt: now
        )
        let artistNames = match.artists.isEmpty
            ? (match.artistDisplay.isEmpty ? [] : [match.artistDisplay])
            : match.artists
        let artists = artistNames.map { Artist(id: UUID().uuidString, name: $0) }
        let tracks = match.tracks.enumerated().map { index, track in
            Track(
                id: UUID().uuidString,
                releaseID: id,
                position: track.position,
                side: track.position.flatMap { $0.first.map(String.init) },
                title: track.title,
                durationSeconds: track.durationSeconds,
                trackIndex: index
            )
        }
        return RecordDetail(release: release, artists: artists, labels: match.labels, tracks: tracks)
    }
}
