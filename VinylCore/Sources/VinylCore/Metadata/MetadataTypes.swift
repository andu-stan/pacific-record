import Foundation

/// Which online database a match came from.
public enum MetadataSource: String, Sendable, Equatable, Codable {
    case discogs
    case musicbrainz
}

public enum MetadataError: Error, Equatable {
    case invalidURL
    case http(status: Int)
    case noResults
}

/// A single track from an online lookup (pre-persistence, no database id).
public struct TrackInfo: Sendable, Equatable {
    public var position: String?
    public var title: String
    public var durationSeconds: Int?

    public init(position: String? = nil, title: String, durationSeconds: Int? = nil) {
        self.position = position
        self.title = title
        self.durationSeconds = durationSeconds
    }
}

/// A provider-agnostic lookup result. The confirm/match screen shows a list of
/// these (often several pressings share a barcode); the chosen one is enriched
/// and turned into a `RecordDetail` for saving.
public struct MetadataMatch: Sendable, Equatable, Identifiable {
    /// Stable per source, e.g. "discogs:249504" or "mb:<uuid>".
    public var id: String
    public var source: MetadataSource
    public var title: String
    public var artistDisplay: String
    public var artists: [String]
    public var year: Int?
    public var country: String?
    public var genre: String?
    public var styles: [String]
    public var format: String?
    public var speed: String?
    public var labels: [LabelCredit]
    public var barcode: String?
    public var discogsReleaseID: Int?
    public var musicbrainzMBID: String?
    public var coverImageURL: URL?
    public var tracks: [TrackInfo]

    public init(
        id: String,
        source: MetadataSource,
        title: String,
        artistDisplay: String,
        artists: [String] = [],
        year: Int? = nil,
        country: String? = nil,
        genre: String? = nil,
        styles: [String] = [],
        format: String? = nil,
        speed: String? = nil,
        labels: [LabelCredit] = [],
        barcode: String? = nil,
        discogsReleaseID: Int? = nil,
        musicbrainzMBID: String? = nil,
        coverImageURL: URL? = nil,
        tracks: [TrackInfo] = []
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.artistDisplay = artistDisplay
        self.artists = artists
        self.year = year
        self.country = country
        self.genre = genre
        self.styles = styles
        self.format = format
        self.speed = speed
        self.labels = labels
        self.barcode = barcode
        self.discogsReleaseID = discogsReleaseID
        self.musicbrainzMBID = musicbrainzMBID
        self.coverImageURL = coverImageURL
        self.tracks = tracks
    }

    /// Convenience: the catalogue number of the first credited label.
    public var primaryCatalogNumber: String? {
        labels.first?.catalogNumber
    }
}

/// A source of record metadata. Barcode/text searches return candidate
/// matches; `enrich(_:)` fills in the tracklist and highest-resolution cover
/// for a chosen candidate.
public protocol MetadataProvider: Sendable {
    var source: MetadataSource { get }
    func searchByBarcode(_ barcode: String) async throws -> [MetadataMatch]
    func searchByText(_ query: String) async throws -> [MetadataMatch]
    func enrich(_ match: MetadataMatch) async throws -> MetadataMatch
}

/// Throttles calls so we stay within an API's rate limit (e.g. Discogs and
/// MusicBrainz both want roughly one request per second).
public actor RateLimiter {
    private let minInterval: TimeInterval
    private var lastCall: Date?

    public init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    /// Suspends until at least `minInterval` has elapsed since the previous
    /// turn, then records this call as the new reference point.
    public func waitForTurn() async {
        if minInterval > 0, let last = lastCall {
            let remaining = minInterval - Date().timeIntervalSince(last)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
        lastCall = Date()
    }
}
