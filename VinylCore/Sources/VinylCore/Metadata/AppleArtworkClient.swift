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
    /// confident match.
    public func artworkURL(artist: String, title: String) async throws -> URL? {
        let term = "\(artist) \(title)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let url = components?.url else { return nil }

        let data = try await http.data(from: url, headers: ["Accept": "application/json"])
        let response = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        guard let best = Self.bestMatch(in: response.results, artist: artist, title: title) else { return nil }
        return Self.highResURL(from: best.artworkUrl100, size: pixelSize)
    }

    /// iTunes returns a 100×100 thumbnail URL; swap the size token for a larger
    /// one — Apple's CDN serves the requested size from the source artwork.
    static func highResURL(from artworkUrl100: String?, size: Int) -> URL? {
        guard let artworkUrl100 else { return nil }
        let hires = artworkUrl100.replacingOccurrences(of: "100x100bb", with: "\(size)x\(size)bb")
        return URL(string: hires)
    }

    /// Picks the album whose artist and title best match, requiring a confident
    /// score so a wrong cover is never substituted.
    static func bestMatch(in results: [ITunesAlbum], artist: String, title: String) -> ITunesAlbum? {
        let wantTitle = normalize(title)
        let wantArtist = normalize(artist)

        func score(_ album: ITunesAlbum) -> Int {
            let albumTitle = normalize(album.collectionName ?? "")
            let albumArtist = normalize(album.artistName ?? "")
            var score = 0
            if !wantTitle.isEmpty {
                if albumTitle == wantTitle { score += 3 }
                else if albumTitle.contains(wantTitle) || wantTitle.contains(albumTitle) { score += 2 }
            }
            if !wantArtist.isEmpty {
                if albumArtist == wantArtist { score += 3 }
                else if albumArtist.contains(wantArtist) || wantArtist.contains(albumArtist) { score += 1 }
            }
            return score
        }

        let ranked = results
            .map { (album: $0, score: score($0)) }
            .sorted { $0.score > $1.score }
        guard let top = ranked.first, top.score >= 3 else { return nil }
        return top.album
    }

    static func normalize(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
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
