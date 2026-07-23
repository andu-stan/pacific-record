import Foundation

/// Fetches front cover art from the Cover Art Archive (the MusicBrainz artwork
/// service), keyed by a release MBID. Prefers a large thumbnail and forces
/// HTTPS (the JSON sometimes returns http URLs, which iOS App Transport
/// Security would block).
public struct CoverArtArchiveClient {
    private let http: HTTPClient

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    /// The best available front-cover URL for a release, or nil if the archive
    /// has no front image (a 404 throws and is treated as "no art" by callers).
    public func frontCoverURL(mbid: String) async throws -> URL? {
        guard let url = URL(string: "https://coverartarchive.org/release/\(mbid)") else { return nil }
        let data = try await http.data(from: url, headers: ["Accept": "application/json"])
        let response = try JSONDecoder().decode(CAAResponse.self, from: data)

        let front = response.images.first(where: { $0.front == true }) ?? response.images.first
        guard let front else { return nil }
        let candidate = front.thumbnails?["1200"]
            ?? front.thumbnails?["large"]
            ?? front.thumbnails?["500"]
            ?? front.image
        guard let candidate else { return nil }
        return URL(string: Self.forcingHTTPS(candidate))
    }

    static func forcingHTTPS(_ string: String) -> String {
        string.hasPrefix("http://") ? "https://" + string.dropFirst("http://".count) : string
    }
}

// MARK: - Cover Art Archive JSON

struct CAAResponse: Decodable {
    let images: [CAAImage]
}

struct CAAImage: Decodable {
    let front: Bool?
    let image: String?
    let thumbnails: [String: String]?
}
