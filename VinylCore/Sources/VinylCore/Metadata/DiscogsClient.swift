import Foundation

/// Looks records up on Discogs — the primary metadata source. Search returns
/// candidate pressings; `enrich(_:)` fetches the full release for a chosen one.
///
/// Requires a personal access token (created at discogs.com/settings/developers)
/// and a descriptive User-Agent, per Discogs' API terms.
public struct DiscogsClient: MetadataProvider {
    public let source: MetadataSource = .discogs

    private let token: String
    private let userAgent: String
    private let http: HTTPClient
    private let limiter: RateLimiter
    private let baseURL = URL(string: "https://api.discogs.com")!

    public init(
        token: String,
        userAgent: String = "PacificRecord/1.0 +https://github.com/andu-stan/pacific-record",
        http: HTTPClient = URLSessionHTTPClient(),
        limiter: RateLimiter = RateLimiter(minInterval: 1.1)
    ) {
        self.token = token
        self.userAgent = userAgent
        self.http = http
        self.limiter = limiter
    }

    private var headers: [String: String] {
        var headers = [
            "User-Agent": userAgent,
            "Accept": "application/json",
        ]
        // Unauthenticated requests still work for public reads (release, search)
        // at a lower rate limit; price suggestions require a token.
        if !token.isEmpty {
            headers["Authorization"] = "Discogs token=\(token)"
        }
        return headers
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static let plainDecoder = JSONDecoder()

    // MARK: - MetadataProvider

    public func searchByBarcode(_ barcode: String) async throws -> [MetadataMatch] {
        try await search(queryItems: [
            URLQueryItem(name: "barcode", value: barcode),
            URLQueryItem(name: "type", value: "release"),
        ])
    }

    public func searchByText(_ query: String) async throws -> [MetadataMatch] {
        try await search(queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "release"),
        ])
    }

    public func enrich(_ match: MetadataMatch) async throws -> MetadataMatch {
        guard match.source == .discogs, let releaseID = match.discogsReleaseID else { return match }
        await limiter.waitForTurn()
        let url = baseURL.appendingPathComponent("releases/\(releaseID)")
        let data = try await http.data(from: url, headers: headers)
        let detail = try Self.decoder.decode(DiscogsReleaseDetail.self, from: data)
        return Self.map(detail: detail, fallback: match)
    }

    // MARK: - Marketplace value

    /// Suggested sale prices per Goldmine condition. Requires a token with
    /// marketplace access; returns an empty dictionary if none are available.
    public func priceSuggestions(releaseID: Int) async throws -> [Condition: Money] {
        await limiter.waitForTurn()
        let url = baseURL.appendingPathComponent("marketplace/price_suggestions/\(releaseID)")
        let data = try await http.data(from: url, headers: headers)
        let raw = try Self.plainDecoder.decode([String: DiscogsPriceSuggestion].self, from: data)
        var result: [Condition: Money] = [:]
        for (key, price) in raw {
            if let condition = Condition(discogsPriceKey: key) {
                result[condition] = Money(amount: price.value, currency: price.currency)
            }
        }
        return result
    }

    /// The lowest current marketplace listing for a release (any condition),
    /// read from the release resource. Works unauthenticated.
    public func lowestListingPrice(releaseID: Int) async throws -> Money? {
        await limiter.waitForTurn()
        let url = baseURL.appendingPathComponent("releases/\(releaseID)")
        let data = try await http.data(from: url, headers: headers)
        let detail = try Self.decoder.decode(DiscogsReleaseDetail.self, from: data)
        guard let price = detail.lowestPrice else { return nil }
        return Money(amount: price, currency: "USD")
    }

    // MARK: - Networking

    private func search(queryItems: [URLQueryItem]) async throws -> [MetadataMatch] {
        await limiter.waitForTurn()
        var components = URLComponents(
            url: baseURL.appendingPathComponent("database/search"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems
        guard let url = components?.url else { throw MetadataError.invalidURL }
        let data = try await http.data(from: url, headers: headers)
        let response = try Self.decoder.decode(DiscogsSearchResponse.self, from: data)
        return response.results.map(Self.map(searchResult:))
    }

    // MARK: - Mapping

    static func map(searchResult result: DiscogsSearchResult) -> MetadataMatch {
        let (artist, title) = splitArtistTitle(result.title ?? "")
        let labels = (result.label ?? []).enumerated().map { index, name in
            LabelCredit(name: name, catalogNumber: index == 0 ? result.catno : nil)
        }
        return MetadataMatch(
            id: "discogs:\(result.id)",
            source: .discogs,
            title: title,
            artistDisplay: artist,
            artists: artist.isEmpty ? [] : [artist],
            year: result.year.flatMap { Int($0) },
            country: result.country,
            genre: result.genre?.first,
            styles: result.style ?? [],
            format: formatToken(from: result.format),
            speed: speedToken(from: result.format),
            labels: labels,
            barcode: result.barcode?.first,
            discogsReleaseID: result.id,
            coverImageURL: result.coverImage.flatMap { URL(string: $0) },
            tracks: []
        )
    }

    static func map(detail: DiscogsReleaseDetail, fallback: MetadataMatch) -> MetadataMatch {
        let rawArtists = (detail.artists ?? []).compactMap(\.name).filter { !$0.isEmpty }
        let artists = cleanArtistNames(rawArtists)
        let artistDisplay = artists.isEmpty ? fallback.artistDisplay : artists.joined(separator: ", ")
        let labels = (detail.labels ?? []).compactMap { label -> LabelCredit? in
            guard let name = label.name else { return nil }
            return LabelCredit(name: name, catalogNumber: label.catno)
        }
        let descriptions = (detail.formats ?? []).flatMap { $0.descriptions ?? [] }
        let barcode = (detail.identifiers ?? [])
            .first { ($0.type ?? "").lowercased() == "barcode" }?.value

        return MetadataMatch(
            id: "discogs:\(detail.id)",
            source: .discogs,
            title: detail.title,
            artistDisplay: artistDisplay,
            artists: artists.isEmpty ? fallback.artists : artists,
            year: detail.year ?? fallback.year,
            country: detail.country ?? fallback.country,
            genre: detail.genres?.first ?? fallback.genre,
            styles: detail.styles ?? fallback.styles,
            format: formatToken(from: descriptions) ?? fallback.format,
            speed: speedToken(from: descriptions) ?? fallback.speed,
            labels: labels.isEmpty ? fallback.labels : labels,
            barcode: barcode ?? fallback.barcode,
            discogsReleaseID: detail.id,
            musicbrainzMBID: fallback.musicbrainzMBID,
            coverImageURL: primaryImageURL(detail.images) ?? fallback.coverImageURL,
            tracks: (detail.tracklist ?? []).compactMap { track in
                guard let title = track.title, !title.isEmpty else { return nil }
                return TrackInfo(position: track.position, title: title, durationSeconds: parseDuration(track.duration))
            }
        )
    }

    // Discogs search titles are "Artist - Title".
    static func splitArtistTitle(_ combined: String) -> (artist: String, title: String) {
        if let range = combined.range(of: " - ") {
            let artist = combined[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let title = combined[range.upperBound...].trimmingCharacters(in: .whitespaces)
            return (artist, title)
        }
        return ("", combined.trimmingCharacters(in: .whitespaces))
    }

    // Strip Discogs' " (2)" style disambiguation suffixes.
    static func cleanArtistNames(_ names: [String]) -> [String] {
        names.map { name in
            if let range = name.range(of: #" \(\d+\)$"#, options: .regularExpression) {
                return String(name[..<range.lowerBound])
            }
            return name
        }
    }

    static func formatToken(from values: [String]?) -> String? {
        guard let values = values else { return nil }
        let priorities = ["LP", "EP", "7\"", "10\"", "12\"", "Single", "Box Set"]
        for candidate in priorities where values.contains(candidate) {
            return candidate
        }
        return values.first { $0 != "Vinyl" } ?? values.first
    }

    static func speedToken(from values: [String]?) -> String? {
        values?.first { $0.range(of: "RPM", options: .caseInsensitive) != nil }
    }

    static func primaryImageURL(_ images: [DiscogsImage]?) -> URL? {
        guard let images = images, !images.isEmpty else { return nil }
        let primary = images.first { ($0.type ?? "") == "primary" } ?? images.first
        return primary?.uri.flatMap { URL(string: $0) }
    }

    // "9:22" -> 562, "1:02:03" -> 3723.
    static func parseDuration(_ value: String?) -> Int? {
        guard let value = value, !value.isEmpty else { return nil }
        let parts = value.split(separator: ":").map { Int($0) }
        guard parts.allSatisfy({ $0 != nil }) else { return nil }
        let numbers = parts.compactMap { $0 }
        switch numbers.count {
        case 2: return numbers[0] * 60 + numbers[1]
        case 3: return numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
        default: return nil
        }
    }
}

// MARK: - Discogs JSON

struct DiscogsSearchResponse: Decodable {
    let results: [DiscogsSearchResult]
}

struct DiscogsSearchResult: Decodable {
    let id: Int
    let title: String?
    let year: String?
    let country: String?
    let format: [String]?
    let label: [String]?
    let genre: [String]?
    let style: [String]?
    let catno: String?
    let barcode: [String]?
    let thumb: String?
    let coverImage: String?
}

struct DiscogsReleaseDetail: Decodable {
    let id: Int
    let title: String
    let year: Int?
    let country: String?
    let genres: [String]?
    let styles: [String]?
    let artists: [DiscogsArtist]?
    let labels: [DiscogsLabel]?
    let formats: [DiscogsFormat]?
    let identifiers: [DiscogsIdentifier]?
    let images: [DiscogsImage]?
    let tracklist: [DiscogsTrack]?
    let lowestPrice: Double?
    let numForSale: Int?
}

struct DiscogsPriceSuggestion: Decodable {
    let currency: String
    let value: Double
}

struct DiscogsArtist: Decodable {
    let name: String?
}

struct DiscogsLabel: Decodable {
    let name: String?
    let catno: String?
}

struct DiscogsFormat: Decodable {
    let name: String?
    let qty: String?
    let descriptions: [String]?
    let text: String?
}

struct DiscogsIdentifier: Decodable {
    let type: String?
    let value: String?
}

struct DiscogsImage: Decodable {
    let type: String?
    let uri: String?
    let uri150: String?
    let width: Int?
    let height: Int?
}

struct DiscogsTrack: Decodable {
    let position: String?
    let title: String?
    let duration: String?
}
