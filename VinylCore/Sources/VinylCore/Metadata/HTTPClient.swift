import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A minimal seam over HTTP GET so the metadata clients can be unit-tested
/// offline: production uses `URLSessionHTTPClient`, tests inject a stub.
public protocol HTTPClient: Sendable {
    func data(from url: URL, headers: [String: String]) async throws -> Data
}

/// `HTTPClient` backed by `URLSession`.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(from url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
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
