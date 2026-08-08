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
    private let mediums: MediumFilter
    private let http: HTTPClient
    private let limiter: RateLimiter
    private let baseURL = URL(string: "https://api.discogs.com")!

    public init(
        token: String,
        userAgent: String = "PacificRecord/1.0 +https://github.com/andu-stan/pacific-record",
        mediums: MediumFilter = .all,
        http: HTTPClient = URLSessionHTTPClient(),
        limiter: RateLimiter = RateLimiter(minInterval: 1.1)
    ) {
        self.token = token
        self.userAgent = userAgent
        self.mediums = mediums
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
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "release"),
        ]
        // Narrow server-side when the user collects a single medium, so the one
        // page we read isn't mostly CDs. Callers still filter what comes back —
        // a barcode lookup deliberately doesn't narrow, and mixed selections
        // can't be expressed as one `format` value.
        if let format = mediums.discogsSearchFormat {
            items.append(URLQueryItem(name: "format", value: format))
        }
        return try await search(queryItems: items)
    }

    public func enrich(_ match: MetadataMatch) async throws -> MetadataMatch {
        guard match.source == .discogs, let releaseID = match.discogsReleaseID else { return match }
        await limiter.waitForTurn()
        let url = baseURL.appendingPathComponent("releases/\(releaseID)")
        let data = try await http.data(from: url, headers: headers)
        let detail = try Self.decoder.decode(DiscogsReleaseDetail.self, from: data)
        return Self.map(detail: detail, fallback: match)
    }

    /// Lowest listing *and* how many copies are for sale, from a single release
    /// read — what wishlist tracking needs to show price and availability.
    public func marketplaceSnapshot(releaseID: Int, currency: String? = nil) async throws -> (price: Money?, numForSale: Int) {
        await limiter.waitForTurn()
        var components = URLComponents(
            url: baseURL.appendingPathComponent("releases/\(releaseID)"),
            resolvingAgainstBaseURL: false
        )
        if let currency, DiscogsCurrency.isSupported(currency) {
            components?.queryItems = [URLQueryItem(name: "curr_abbr", value: currency)]
        }
        guard let url = components?.url else { throw MetadataError.invalidURL }
        let data = try await http.data(from: url, headers: headers)
        let detail = try Self.decoder.decode(DiscogsReleaseDetail.self, from: data)
        let money = detail.lowestPrice.map { Money(amount: $0, currency: currency ?? "USD") }
        return (money, detail.numForSale ?? 0)
    }

    // MARK: - Images

    /// Every image for a release (front, back, labels…), primary first — for the
    /// cover picker, where the single primary cover isn't enough. Each carries a
    /// full-size URL plus a 150px thumbnail. Works unauthenticated (public read).
    public func images(releaseID: Int) async throws -> [RemoteImage] {
        await limiter.waitForTurn()
        let url = baseURL.appendingPathComponent("releases/\(releaseID)")
        let data = try await http.data(from: url, headers: headers)
        let detail = try Self.decoder.decode(DiscogsReleaseDetail.self, from: data)
        return Self.orderedImages(detail.images)
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
    /// read from the release resource. Works unauthenticated. Discogs converts
    /// the price when given a `curr_abbr`; see `DiscogsCurrency`.
    public func lowestListingPrice(releaseID: Int, currency: String? = nil) async throws -> Money? {
        await limiter.waitForTurn()
        var components = URLComponents(
            url: baseURL.appendingPathComponent("releases/\(releaseID)"),
            resolvingAgainstBaseURL: false
        )
        if let currency, DiscogsCurrency.isSupported(currency) {
            components?.queryItems = [URLQueryItem(name: "curr_abbr", value: currency)]
        }
        guard let url = components?.url else { throw MetadataError.invalidURL }
        let data = try await http.data(from: url, headers: headers)
        let detail = try Self.decoder.decode(DiscogsReleaseDetail.self, from: data)
        guard let price = detail.lowestPrice else { return nil }
        // Discogs echoes the currency it priced in; fall back to the request.
        return Money(amount: price, currency: currency ?? "USD")
    }

    // MARK: - Collection

    /// The authenticated user's Discogs username (derived from the token), so a
    /// collection import doesn't need the user to type it.
    public func identity() async throws -> String {
        await limiter.waitForTurn()
        let url = baseURL.appendingPathComponent("oauth/identity")
        let data = try await http.data(from: url, headers: headers)
        return try Self.decoder.decode(DiscogsIdentity.self, from: data).username
    }

    /// The collection's "Media/Sleeve Condition" custom-field ids, if the user
    /// created those fields, so grades can be mapped during import.
    public func collectionFieldIDs(username: String) async throws -> CollectionFieldIDs {
        await limiter.waitForTurn()
        let url = baseURL.appendingPathComponent("users/\(username)/collection/fields")
        let data = try await http.data(from: url, headers: headers)
        let response = try Self.decoder.decode(DiscogsFieldsResponse.self, from: data)
        var media: Int?
        var sleeve: Int?
        for field in response.fields {
            let name = (field.name ?? "").lowercased()
            if name.contains("media") { media = field.id }
            else if name.contains("sleeve") { sleeve = field.id }
        }
        return CollectionFieldIDs(media: media, sleeve: sleeve)
    }

    /// One page of the user's collection (folder 0 = "All"), mapped to importable
    /// entries. `perPage` maxes out at 100 on Discogs.
    public func collectionPage(
        username: String,
        folderID: Int = 0,
        page: Int,
        perPage: Int = 100,
        mediaFieldID: Int? = nil,
        sleeveFieldID: Int? = nil
    ) async throws -> CollectionPage {
        await limiter.waitForTurn()
        var components = URLComponents(
            url: baseURL.appendingPathComponent("users/\(username)/collection/folders/\(folderID)/releases"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "sort", value: "artist"),
            URLQueryItem(name: "sort_order", value: "asc"),
        ]
        guard let url = components?.url else { throw MetadataError.invalidURL }
        let data = try await http.data(from: url, headers: headers)
        let response = try Self.decoder.decode(DiscogsCollectionResponse.self, from: data)
        let items = response.releases.map {
            Self.map(collectionRelease: $0, mediaFieldID: mediaFieldID, sleeveFieldID: sleeveFieldID)
        }
        return CollectionPage(
            items: items,
            page: response.pagination.page,
            totalPages: response.pagination.pages,
            totalItems: response.pagination.items
        )
    }

    static func map(collectionRelease release: DiscogsCollectionRelease, mediaFieldID: Int?, sleeveFieldID: Int?) -> CollectionEntry {
        let info = release.basicInformation
        let artists = cleanArtistNames((info.artists ?? []).compactMap(\.name).filter { !$0.isEmpty })
        let labels = (info.labels ?? []).compactMap { label -> LabelCredit? in
            guard let name = label.name else { return nil }
            return LabelCredit(name: name, catalogNumber: label.catno)
        }
        let descriptions = (info.formats ?? []).flatMap { $0.descriptions ?? [] }
        let match = MetadataMatch(
            id: "discogs:\(release.id)",
            source: .discogs,
            title: info.title ?? "",
            artistDisplay: artists.joined(separator: ", "),
            artists: artists,
            year: info.year,
            country: nil,
            genre: info.genres?.first,
            styles: info.styles ?? [],
            format: formatToken(from: descriptions),
            speed: speedToken(from: descriptions),
            mediums: mediumNames(from: info.formats),
            labels: labels,
            barcode: nil,
            discogsReleaseID: release.id,
            musicbrainzMBID: nil,
            coverImageURL: (info.coverImage ?? info.thumb).flatMap { URL(string: $0) },
            tracks: []
        )
        var media: Condition?
        var sleeve: Condition?
        for note in release.notes ?? [] {
            if let mediaFieldID, note.fieldId == mediaFieldID { media = Condition(discogsPriceKey: note.value) }
            if let sleeveFieldID, note.fieldId == sleeveFieldID { sleeve = Condition(discogsPriceKey: note.value) }
        }
        let rating = min(5, max(0, release.rating ?? 0))
        return CollectionEntry(match: match, rating: rating, mediaCondition: media, sleeveCondition: sleeve)
    }

    // MARK: - Collection writes

    /// True if the release is already in the user's collection (any folder), so
    /// sync-back can avoid creating duplicate instances.
    public func collectionContains(username: String, releaseID: Int) async throws -> Bool {
        await limiter.waitForTurn()
        let url = baseURL.appendingPathComponent("users/\(username)/collection/releases/\(releaseID)")
        let data = try await http.data(from: url, headers: headers)
        return try Self.decoder.decode(DiscogsCollectionReleaseLookup.self, from: data).pagination.items > 0
    }

    /// Adds a release to the user's collection (folder 1 = "Uncategorized" by
    /// default) and returns the new instance id. Requires a token with write
    /// access (a personal access token has it).
    @discardableResult
    public func addToCollection(username: String, releaseID: Int, folderID: Int = 1) async throws -> Int {
        await limiter.waitForTurn()
        let url = baseURL.appendingPathComponent("users/\(username)/collection/folders/\(folderID)/releases/\(releaseID)")
        let data = try await http.data(from: url, method: "POST", body: nil, headers: headers)
        return try Self.decoder.decode(DiscogsAddInstance.self, from: data).instanceId
    }

    /// Sets the star rating on a collection instance (best-effort).
    public func setCollectionRating(username: String, releaseID: Int, instanceID: Int, folderID: Int = 1, rating: Int) async throws {
        await limiter.waitForTurn()
        let url = baseURL.appendingPathComponent(
            "users/\(username)/collection/folders/\(folderID)/releases/\(releaseID)/instances/\(instanceID)")
        let body = try JSONSerialization.data(withJSONObject: ["rating": rating])
        var writeHeaders = headers
        writeHeaders["Content-Type"] = "application/json"
        _ = try await http.data(from: url, method: "POST", body: body, headers: writeHeaders)
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
            mediums: mediumTokens(from: result.format),
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
        let mediums = mediumNames(from: detail.formats)
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
            mediums: mediums.isEmpty ? fallback.mediums : mediums,
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

    /// The medium names of a release ("Vinyl", "CD", "Cassette"), in order and
    /// without repeats. A release object names its media explicitly, so keep
    /// them all — even ones outside our vocabulary, which read as "unknown".
    static func mediumNames(from formats: [DiscogsFormat]?) -> [String] {
        var names: [String] = []
        for name in (formats ?? []).compactMap(\.name) where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    /// Search results flatten the medium in with the format descriptions
    /// (`["Vinyl", "LP", "Album"]`), so pick out only the entries we recognise
    /// as media — "LP" and "Album" describe the pressing, not what it's made of.
    static func mediumTokens(from values: [String]?) -> [String] {
        var names: [String] = []
        for value in values ?? [] where ReleaseMedium.named(value) != nil && !names.contains(value) {
            names.append(value)
        }
        return names
    }

    static func primaryImageURL(_ images: [DiscogsImage]?) -> URL? {
        guard let images = images, !images.isEmpty else { return nil }
        let primary = images.first { ($0.type ?? "") == "primary" } ?? images.first
        return primary?.uri.flatMap { URL(string: $0) }
    }

    /// All release images, the primary (front) moved first, other images kept in
    /// their original order.
    static func orderedImages(_ images: [DiscogsImage]?) -> [RemoteImage] {
        guard let images else { return [] }
        let primary = images.filter { ($0.type ?? "") == "primary" }
        let others = images.filter { ($0.type ?? "") != "primary" }
        return (primary + others).compactMap { image in
            guard let uri = image.uri, let full = URL(string: uri) else { return nil }
            return RemoteImage(full: full, thumbnail: image.uri150.flatMap { URL(string: $0) })
        }
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

// MARK: - Currency

/// Currencies Discogs will convert marketplace prices into (`curr_abbr`).
///
/// Note this only applies to the *lowest listing* lookup. Discogs returns
/// per-condition price **suggestions** in the currency configured on the
/// account that owns the API token, and offers no way to override it.
public enum DiscogsCurrency {
    public static let supported = [
        "USD", "GBP", "EUR", "CAD", "AUD", "JPY",
        "CHF", "MXN", "BRL", "NZD", "SEK", "ZAR",
    ]

    public static func isSupported(_ code: String) -> Bool {
        supported.contains(code.uppercased())
    }
}

// MARK: - Collection types

/// One page of a user's Discogs collection, mapped for import.
public struct CollectionPage: Sendable {
    public let items: [CollectionEntry]
    public let page: Int
    public let totalPages: Int
    public let totalItems: Int
}

/// A single collection item ready to import: the release metadata plus the
/// user's Discogs rating and, if they grade in Discogs, media/sleeve condition.
public struct CollectionEntry: Sendable {
    public let match: MetadataMatch
    public let rating: Int
    public let mediaCondition: Condition?
    public let sleeveCondition: Condition?
}

/// The custom-field ids Discogs uses for media/sleeve grades in a collection.
public struct CollectionFieldIDs: Sendable {
    public let media: Int?
    public let sleeve: Int?
}

// MARK: - Discogs JSON

struct DiscogsSearchResponse: Decodable {
    let results: [DiscogsSearchResult]
}

struct DiscogsIdentity: Decodable {
    let username: String
}

struct DiscogsCollectionResponse: Decodable {
    let pagination: DiscogsPagination
    let releases: [DiscogsCollectionRelease]
}

struct DiscogsPagination: Decodable {
    let page: Int
    let pages: Int
    let items: Int
}

struct DiscogsCollectionRelease: Decodable {
    let id: Int
    let rating: Int?
    let basicInformation: DiscogsBasicInformation
    let notes: [DiscogsCollectionNote]?
}

struct DiscogsCollectionNote: Decodable {
    let fieldId: Int
    let value: String
}

struct DiscogsBasicInformation: Decodable {
    let title: String?
    let year: Int?
    let thumb: String?
    let coverImage: String?
    let formats: [DiscogsFormat]?
    let labels: [DiscogsLabel]?
    let artists: [DiscogsArtist]?
    let genres: [String]?
    let styles: [String]?
}

struct DiscogsFieldsResponse: Decodable {
    let fields: [DiscogsField]
}

struct DiscogsField: Decodable {
    let id: Int
    let name: String?
}

struct DiscogsAddInstance: Decodable {
    let instanceId: Int
}

struct DiscogsCollectionReleaseLookup: Decodable {
    let pagination: DiscogsPagination
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
