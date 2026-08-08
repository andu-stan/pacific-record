import Foundation

/// Looks records up on MusicBrainz — the fallback source when Discogs has no
/// match. Cover art comes from the Cover Art Archive by release MBID.
///
/// MusicBrainz requires a descriptive User-Agent and asks for no more than one
/// request per second.
public struct MusicBrainzClient: MetadataProvider {
    public let source: MetadataSource = .musicbrainz

    private let userAgent: String
    private let http: HTTPClient
    private let limiter: RateLimiter
    private let baseURL = URL(string: "https://musicbrainz.org/ws/2")!

    public init(
        userAgent: String = "PacificRecord/1.0 ( https://github.com/andu-stan/pacific-record )",
        http: HTTPClient = URLSessionHTTPClient(),
        limiter: RateLimiter = RateLimiter(minInterval: 1.1)
    ) {
        self.userAgent = userAgent
        self.http = http
        self.limiter = limiter
    }

    private var headers: [String: String] {
        ["User-Agent": userAgent, "Accept": "application/json"]
    }

    private static let decoder = JSONDecoder()

    // MARK: - MetadataProvider

    public func searchByBarcode(_ barcode: String) async throws -> [MetadataMatch] {
        try await search(query: "barcode:\(barcode)")
    }

    public func searchByText(_ query: String) async throws -> [MetadataMatch] {
        try await search(query: query)
    }

    public func enrich(_ match: MetadataMatch) async throws -> MetadataMatch {
        guard match.source == .musicbrainz, let mbid = match.musicbrainzMBID else { return match }
        await limiter.waitForTurn()
        var components = URLComponents(
            url: baseURL.appendingPathComponent("release/\(mbid)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "inc", value: "recordings+labels+artist-credits"),
        ]
        guard let url = components?.url else { return match }
        let data = try await http.data(from: url, headers: headers)
        let release = try Self.decoder.decode(MBRelease.self, from: data)
        return Self.map(release: release)
    }

    // MARK: - Networking

    private func search(query: String) async throws -> [MetadataMatch] {
        await limiter.waitForTurn()
        var components = URLComponents(
            url: baseURL.appendingPathComponent("release"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "25"),
        ]
        guard let url = components?.url else { throw MetadataError.invalidURL }
        let data = try await http.data(from: url, headers: headers)
        let response = try Self.decoder.decode(MBSearchResponse.self, from: data)
        return response.releases.map(Self.map(release:))
    }

    // MARK: - Mapping

    static func map(release: MBRelease) -> MetadataMatch {
        let credits = release.artistCredit ?? []
        let artistDisplay = credits
            .map { ($0.name ?? "") + ($0.joinphrase ?? "") }
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let artists = credits.compactMap(\.name).filter { !$0.isEmpty }
        let labels = (release.labelInfo ?? []).compactMap { info -> LabelCredit? in
            let name = info.label?.name
            let catalog = info.catalogNumber
            guard name != nil || catalog != nil else { return nil }
            return LabelCredit(name: name ?? "Unknown", catalogNumber: catalog)
        }
        let tracks = (release.media ?? [])
            .flatMap { $0.tracks ?? [] }
            .compactMap { track -> TrackInfo? in
                guard let title = track.title else { return nil }
                return TrackInfo(
                    position: track.number,
                    title: title,
                    durationSeconds: track.length.map { $0 / 1000 }
                )
            }

        return MetadataMatch(
            id: "mb:\(release.id)",
            source: .musicbrainz,
            title: release.title,
            artistDisplay: artistDisplay,
            artists: artists,
            year: parseYear(release.date),
            country: release.country,
            styles: [],
            format: (release.media ?? []).compactMap(\.format).first,
            discCount: (release.media ?? []).isEmpty ? nil : (release.media ?? []).count,
            // MusicBrainz qualifies the medium (`12" Vinyl`); `ReleaseMedium`
            // reads through that, so pass the names along as they come.
            mediums: (release.media ?? []).compactMap(\.format),
            labels: labels,
            barcode: release.barcode,
            musicbrainzMBID: release.id,
            coverImageURL: URL(string: "https://coverartarchive.org/release/\(release.id)/front"),
            tracks: tracks
        )
    }

    // "1959" or "1959-08-17" -> 1959.
    static func parseYear(_ value: String?) -> Int? {
        guard let value = value, value.count >= 4 else { return nil }
        return Int(value.prefix(4))
    }
}

// MARK: - MusicBrainz JSON

struct MBSearchResponse: Decodable {
    let releases: [MBRelease]
}

struct MBRelease: Decodable {
    let id: String
    let title: String
    let date: String?
    let country: String?
    let barcode: String?
    let artistCredit: [MBArtistCredit]?
    let labelInfo: [MBLabelInfo]?
    let media: [MBMedium]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case country
        case barcode
        case artistCredit = "artist-credit"
        case labelInfo = "label-info"
        case media
    }
}

struct MBArtistCredit: Decodable {
    let name: String?
    let joinphrase: String?
}

struct MBLabelInfo: Decodable {
    let catalogNumber: String?
    let label: MBLabel?

    enum CodingKeys: String, CodingKey {
        case catalogNumber = "catalog-number"
        case label
    }
}

struct MBLabel: Decodable {
    let name: String?
}

struct MBMedium: Decodable {
    let format: String?
    let tracks: [MBTrack]?
}

struct MBTrack: Decodable {
    let number: String?
    let title: String?
    let length: Int?
}
