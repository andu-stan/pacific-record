import Foundation

/// Fetches cover art from Deezer's public search API — official, label-supplied
/// artwork at 1000×1000, no API key required. Useful as a second opinion when
/// Apple Music has no confident match (different catalogues, different
/// regional availability), and far cleaner than a user-uploaded scan.
///
/// (Amazon is the other obvious catalogue, but its Product Advertising API
/// requires affiliate credentials and signed requests, so it isn't usable from
/// a personal app like this.)
public struct DeezerArtworkClient {
    private let http: HTTPClient

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    /// A high-resolution artwork URL for the album, or nil without a confident
    /// title match (same rule as the Apple client — never guess).
    public func artworkURL(artist: String, title: String) async throws -> URL? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }

        // Deezer supports a fielded query, which is much more precise than a
        // bag of words; fall back to a plain query if it finds nothing.
        var queries: [String] = []
        if !cleanArtist.isEmpty {
            queries.append("artist:\"\(cleanArtist)\" album:\"\(cleanTitle)\"")
        }
        queries.append("\(cleanArtist) \(cleanTitle)".trimmingCharacters(in: .whitespaces))

        for query in queries {
            guard let url = Self.searchURL(query: query) else { continue }
            guard let data = try? await http.data(from: url, headers: ["Accept": "application/json"]),
                  let response = try? JSONDecoder().decode(DeezerSearchResponse.self, from: data),
                  let albums = response.data, !albums.isEmpty
            else { continue }

            let best = ArtworkMatching.bestMatch(
                in: albums,
                title: cleanTitle,
                artist: cleanArtist,
                titleOf: { $0.title ?? "" },
                artistOf: { $0.artist?.name ?? "" }
            )
            if let string = best?.bestCover, let coverURL = URL(string: string) {
                return coverURL
            }
        }
        return nil
    }

    static func searchURL(query: String) -> URL? {
        var components = URLComponents(string: "https://api.deezer.com/search/album")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "25"),
        ]
        return components?.url
    }
}

// MARK: - Deezer JSON

struct DeezerSearchResponse: Decodable {
    // Optional: Deezer returns an `error` object instead of `data` on failure.
    let data: [DeezerAlbum]?
}

struct DeezerAlbum: Decodable {
    let title: String?
    let cover: String?
    let coverBig: String?
    let coverXl: String?
    let artist: DeezerArtist?

    enum CodingKeys: String, CodingKey {
        case title
        case cover
        case coverBig = "cover_big"
        case coverXl = "cover_xl"
        case artist
    }

    /// Largest artwork Deezer offers for the album.
    var bestCover: String? {
        [coverXl, coverBig, cover].compactMap { $0 }.first { !$0.isEmpty }
    }
}

struct DeezerArtist: Decodable {
    let name: String?
}
