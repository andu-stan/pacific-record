import XCTest
@testable import VinylCore

final class AppleArtworkClientTests: XCTestCase {
    func testPicksBestMatchAndUpscales() async throws {
        let data = try Fixture.data("itunes_search")
        let client = AppleArtworkClient(http: StubHTTPClient { _ in data }, pixelSize: 1500)
        let url = try await client.artworkURL(artist: "Miles Davis", title: "Kind of Blue")
        XCTAssertEqual(url?.absoluteString,
                       "https://is1-ssl.mzstatic.com/image/thumb/Music/abc/source/1500x1500bb.jpg")
    }

    func testReturnsNilWhenNoConfidentMatch() async throws {
        let data = try Fixture.data("itunes_search")
        let client = AppleArtworkClient(http: StubHTTPClient { _ in data })
        let url = try await client.artworkURL(artist: "Nobody At All", title: "Unknown Record")
        XCTAssertNil(url)
    }

    func testHighResTransform() {
        XCTAssertEqual(
            AppleArtworkClient.highResURL(from: "https://x/y/100x100bb.jpg", size: 1200)?.absoluteString,
            "https://x/y/1200x1200bb.jpg")
    }
}
