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

    /// Apple returns several albums by the same artist; the one whose *title*
    /// matches must win — not merely the first result by that artist.
    func testPicksTheRequestedAlbumNotJustTheArtist() async throws {
        let data = try Fixture.data("itunes_metallica")
        let client = AppleArtworkClient(http: StubHTTPClient { _ in data }, pixelSize: 1500)
        let url = try await client.artworkURL(artist: "Metallica", title: "...And Justice for All")
        XCTAssertEqual(url?.absoluteString,
                       "https://is1-ssl.mzstatic.com/image/thumb/Music/justice/source/1500x1500bb.jpg")
    }

    func testReturnsNilWhenOnlyTheArtistMatches() async throws {
        let data = try Fixture.data("itunes_metallica")
        let client = AppleArtworkClient(http: StubHTTPClient { _ in data })
        // "Load" isn't in the results — a Metallica cover must not be substituted.
        XCTAssertNil(try await client.artworkURL(artist: "Metallica", title: "Load"))
    }

    func testHighResTransform() {
        XCTAssertEqual(
            AppleArtworkClient.highResURL(from: "https://x/y/100x100bb.jpg", size: 1200)?.absoluteString,
            "https://x/y/1200x1200bb.jpg")
        // Apple doesn't always hand back a 100x100 source size.
        XCTAssertEqual(
            AppleArtworkClient.highResURL(from: "https://x/y/60x60bb.jpg", size: 1500)?.absoluteString,
            "https://x/y/1500x1500bb.jpg")
    }
}
