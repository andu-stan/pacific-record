import XCTest
@testable import VinylCore

final class CoverArtArchiveClientTests: XCTestCase {
    func testFrontCoverPrefersLargeThumbnailAndForcesHTTPS() async throws {
        let data = try Fixture.data("caa_release")
        let client = CoverArtArchiveClient(http: StubHTTPClient { _ in data })
        let url = try await client.frontCoverURL(mbid: "mbid")
        XCTAssertEqual(url?.absoluteString, "https://coverartarchive.org/release/mbid/123-1200.jpg")
    }

    func testForcingHTTPS() {
        XCTAssertEqual(CoverArtArchiveClient.forcingHTTPS("http://x/y.jpg"), "https://x/y.jpg")
        XCTAssertEqual(CoverArtArchiveClient.forcingHTTPS("https://x/y.jpg"), "https://x/y.jpg")
    }
}
