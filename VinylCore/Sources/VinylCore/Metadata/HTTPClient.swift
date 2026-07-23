import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A minimal seam over HTTP so the metadata clients can be unit-tested offline:
/// production uses `URLSessionHTTPClient`, tests inject a stub. The primitive is
/// the general request; `data(from:headers:)` is a GET convenience.
public protocol HTTPClient: Sendable {
    func data(from url: URL, method: String, body: Data?, headers: [String: String]) async throws -> Data
}

public extension HTTPClient {
    /// GET convenience used by the read-only metadata lookups.
    func data(from url: URL, headers: [String: String]) async throws -> Data {
        try await data(from: url, method: "GET", body: nil, headers: headers)
    }
}

/// `HTTPClient` backed by `URLSession`.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(from url: URL, method: String, body: Data?, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MetadataError.http(status: http.statusCode)
        }
        return data
    }
}
