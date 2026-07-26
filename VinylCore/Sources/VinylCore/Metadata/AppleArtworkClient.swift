import Foundation

/// Fetches high-resolution cover art from the public iTunes Search API. Apple's
/// artwork is the official, label-supplied digital cover — cleaner and sharper
/// than the user-uploaded scans on Discogs — so it's preferred when it
/// confidently matches the record, with the scan as a fallback.
public struct AppleArtworkClient {
    private let http: HTTPClient
    private let pixelSize: Int

    public init(http: HTTPClient = URLSessionHTTPClient(), pixelSize: Int = 1500) {
        self.http = http
        self.pixelSize = pixelSize
    }

    /// Returns a high-resolution artwork URL for the album, or nil if there's no
    /// confident match. A result must match the *title*; matching only the
    /// artist is never enough (that returns a different album by the same act).
    public func artworkURL(artist: String, title: String) async throws -> URL? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }

        // Try the focused "artist title" query first, then the title alone —
        // punctuation-heavy titles ("...And Justice for All") sometimes rank
        // badly when combined with the artist.
        var queries = ["\(cleanArtist) \(cleanTitle)".trimmingCharacters(in: .whitespaces)]
        if !cleanArtist.isEmpty { queries.append(cleanTitle) }

        for query in queries {
            guard let url = Self.searchURL(term: query) else { continue }
            guard let data = try? await http.data(from: url, headers: ["Accept": "application/json"]),
                  let response = try? JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            else { continue }

            if let best = Self.bestMatch(in: response.results, artist: cleanArtist, title: cleanTitle) {
                return Self.highResURL(from: best.artworkUrl100, size: pixelSize)
            }
        }
        return nil
    }

    static func searchURL(term: String) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "limit", value: "25"),
        ]
        return components?.url
    }

    /// iTunes returns a thumbnail URL with the size baked into the filename
    /// ("…/100x100bb.jpg"); swap it for a larger one — Apple's CDN renders the
    /// requested size from the source artwork.
    static func highResURL(from artworkUrl100: String?, size: Int) -> URL? {
        guard let artworkUrl100 else { return nil }
        // Match any source size, not just 100x100 (Apple varies it).
        let hires = artworkUrl100.replacingOccurrences(
            of: "/[0-9]+x[0-9]+bb",
            with: "/\(size)x\(size)bb",
            options: .regularExpression
        )
        return URL(string: hires)
    }

    /// Picks the album whose title (and then artist) genuinely matches.
    static func bestMatch(in results: [ITunesAlbum], artist: String, title: String) -> ITunesAlbum? {
        ArtworkMatching.bestMatch(
            in: results,
            title: title,
            artist: artist,
            titleOf: { $0.collectionName ?? "" },
            artistOf: { $0.artistName ?? "" }
        )
    }
}

// MARK: - iTunes JSON

struct ITunesSearchResponse: Decodable {
    let results: [ITunesAlbum]
}

struct ITunesAlbum: Decodable {
    let artistName: String?
    let collectionName: String?
    let artworkUrl100: String?
}
