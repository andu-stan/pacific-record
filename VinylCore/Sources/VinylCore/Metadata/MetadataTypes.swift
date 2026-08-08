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
    case responseTooLarge
}

/// A monetary amount in a given ISO currency (e.g. Discogs price data).
public struct Money: Sendable, Equatable {
    public var amount: Double
    public var currency: String

    public init(amount: Double, currency: String) {
        self.amount = amount
        self.currency = currency
    }
}

/// An image for a release from an online source: a full-size URL to download
/// plus an optional lighter thumbnail for grids and pickers.
public struct RemoteImage: Sendable, Equatable {
    public var full: URL
    public var thumbnail: URL?

    public init(full: URL, thumbnail: URL? = nil) {
        self.full = full
        self.thumbnail = thumbnail
    }
}

/// How many people own and want a pressing. The strongest signal for telling
/// near-identical entries apart: the canonical pressing of a popular LP has
/// thousands of owners, an accidental duplicate has a handful.
public struct CommunityStats: Sendable, Equatable {
    public var have: Int
    public var want: Int

    public init(have: Int, want: Int) {
        self.have = have
        self.want = want
    }
}

/// A code printed on or etched into a release — matrix/runout numbers, label
/// codes, rights societies, mastering SIDs. The runout is what a collector
/// reads off the record itself to settle which pressing they're holding.
public struct ReleaseIdentifier: Sendable, Equatable, Identifiable {
    public var type: String
    public var value: String
    /// What the code applies to, when the source says ("Side A", "Runout etching").
    public var note: String?

    public var id: String { "\(type)|\(note ?? "")|\(value)" }

    public init(type: String, value: String, note: String? = nil) {
        self.type = type
        self.value = value
        self.note = note
    }
}

/// A company credited on a release — "Pressed By – Pallas", "Mastered At –
/// Sterling Sound". Two pressings from different plants are different records.
public struct CompanyCredit: Sendable, Equatable, Identifiable {
    public var role: String
    public var name: String

    public var id: String { "\(role)|\(name)" }

    public init(role: String, name: String) {
        self.role = role
        self.name = name
    }
}

/// The pressing-specific facts that separate two otherwise identical entries.
/// Fetched on demand, because each one costs a rate-limited request.
public struct PressingDetail: Sendable, Equatable {
    /// The release date as the source gives it — "1959-08-17" or just "1959".
    public var released: String?
    public var identifiers: [ReleaseIdentifier]
    public var credits: [CompanyCredit]
    public var notes: String?
    public var numForSale: Int
    public var lowestPrice: Money?
    public var imageCount: Int

    public init(
        released: String? = nil,
        identifiers: [ReleaseIdentifier] = [],
        credits: [CompanyCredit] = [],
        notes: String? = nil,
        numForSale: Int = 0,
        lowestPrice: Money? = nil,
        imageCount: Int = 0
    ) {
        self.released = released
        self.identifiers = identifiers
        self.credits = credits
        self.notes = notes
        self.numForSale = numForSale
        self.lowestPrice = lowestPrice
        self.imageCount = imageCount
    }

    /// True when the fetch came back with nothing worth showing.
    public var isEmpty: Bool {
        released == nil && identifiers.isEmpty && credits.isEmpty
            && notes == nil && numForSale == 0 && imageCount == 0
    }
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
    /// Every format descriptor the source lists — "LP", "Album", "Reissue",
    /// "180 Gram", "Gatefold". This is what actually separates two pressings
    /// that show the same label, catalogue number, year and country.
    public var formatDescriptions: [String]
    /// The source's free-text format note: "Blue Translucent", "Club Edition",
    /// "Half-Speed Mastered".
    public var formatText: String?
    /// Number of discs, when the source says — 2 for a 2×LP.
    public var discCount: Int?
    public var speed: String?
    /// The physical media this release was issued on, as the source names them
    /// ("Vinyl", "CD", "Cassette"…). Used to filter searches by medium; empty
    /// when the source doesn't say.
    public var mediums: [String]
    public var labels: [LabelCredit]
    /// The barcode to save with the record.
    public var barcode: String?
    /// Every barcode the source lists, so a scan can be matched exactly against
    /// the candidate that really carries the code.
    public var barcodes: [String]
    public var discogsReleaseID: Int?
    /// The Discogs "master" this belongs to — every pressing of the same album
    /// shares one, which is what links to the full list of versions.
    public var masterID: Int?
    public var musicbrainzMBID: String?
    public var coverImageURL: URL?
    /// How many people own and want this pressing, when the source tracks it.
    public var community: CommunityStats?
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
        formatDescriptions: [String] = [],
        formatText: String? = nil,
        discCount: Int? = nil,
        speed: String? = nil,
        mediums: [String] = [],
        labels: [LabelCredit] = [],
        barcode: String? = nil,
        barcodes: [String] = [],
        discogsReleaseID: Int? = nil,
        masterID: Int? = nil,
        musicbrainzMBID: String? = nil,
        coverImageURL: URL? = nil,
        community: CommunityStats? = nil,
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
        self.formatDescriptions = formatDescriptions
        self.formatText = formatText
        self.discCount = discCount
        self.speed = speed
        self.mediums = mediums
        self.labels = labels
        self.barcode = barcode
        self.barcodes = barcodes.isEmpty ? [barcode].compactMap { $0 } : barcodes
        self.discogsReleaseID = discogsReleaseID
        self.masterID = masterID
        self.musicbrainzMBID = musicbrainzMBID
        self.coverImageURL = coverImageURL
        self.community = community
        self.tracks = tracks
    }

    /// Convenience: the catalogue number of the first credited label.
    public var primaryCatalogNumber: String? {
        labels.first?.catalogNumber
    }

    /// The pressing line for a candidate row — "2×LP, Album, Reissue, 180 Gram,
    /// Blue Translucent". Falls back to the single format token when the source
    /// gives no descriptors.
    public var formatSummary: String? {
        var parts = formatDescriptions
        if let discCount, discCount > 1, let first = parts.first {
            parts[0] = "\(discCount)×\(first)"
        }
        if parts.isEmpty, let format {
            parts = [discCount.map { $0 > 1 ? "\($0)×\(format)" : format } ?? format]
        }
        if let formatText, !formatText.isEmpty, !parts.contains(formatText) {
            parts.append(formatText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// True when this candidate genuinely carries the scanned code, rather than
    /// merely coming back in the same search.
    public func carries(barcode code: String) -> Bool {
        let wanted = Self.normalizedBarcode(code)
        guard !wanted.isEmpty else { return false }
        return barcodes.contains { Self.normalizedBarcode($0) == wanted }
    }

    /// Barcodes are listed with spaces and dashes however the label printed
    /// them ("7 22975 30302 4"), so compare digits only.
    private static func normalizedBarcode(_ raw: String) -> String {
        raw.filter(\.isNumber)
    }

    /// The release's page on the source's website — the escape hatch when two
    /// entries still look alike.
    public var webURL: URL? {
        switch source {
        case .discogs:
            return discogsReleaseID.flatMap { URL(string: "https://www.discogs.com/release/\($0)") }
        case .musicbrainz:
            return musicbrainzMBID.flatMap { URL(string: "https://musicbrainz.org/release/\($0)") }
        }
    }

    /// Every pressing of the same album, on the source's website.
    public var allVersionsURL: URL? {
        guard source == .discogs, let masterID else { return nil }
        return URL(string: "https://www.discogs.com/master/\(masterID)")
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
