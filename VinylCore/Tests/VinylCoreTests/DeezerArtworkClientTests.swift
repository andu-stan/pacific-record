import XCTest
@testable import VinylCore

final class DeezerArtworkClientTests: XCTestCase {
    func testPicksMatchingAlbumAndPrefersLargestCover() async throws {
        let data = try Fixture.data("deezer_search")
        let client = DeezerArtworkClient(http: StubHTTPClient { _ in data })
        let url = try await client.artworkURL(artist: "Metallica", title: "...And Justice for All")
        XCTAssertEqual(url?.absoluteString, "https://cdn.deezer.com/justice/1000x1000.jpg")
    }

    func testReturnsNilWhenOnlyTheArtistMatches() async throws {
        let data = try Fixture.data("deezer_search")
        let client = DeezerArtworkClient(http: StubHTTPClient { _ in data })
        XCTAssertNil(try await client.artworkURL(artist: "Metallica", title: "Reload"))
    }

    func testHandlesErrorPayloadWithoutData() async throws {
        let data = Data(#"{"error":{"type":"Exception","message":"quota"}}"#.utf8)
        let client = DeezerArtworkClient(http: StubHTTPClient { _ in data })
        XCTAssertNil(try await client.artworkURL(artist: "Metallica", title: "Ride the Lightning"))
    }
}
