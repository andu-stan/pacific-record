import XCTest
@testable import VinylCore

final class MusicBrainzClientTests: XCTestCase {
    func testSearchByBarcodeParsesRelease() async throws {
        let data = try Fixture.data("musicbrainz_release")
        let client = MusicBrainzClient(http: StubHTTPClient { _ in data }, limiter: RateLimiter(minInterval: 0))

        let matches = try await client.searchByBarcode("888880000001")
        let match = try XCTUnwrap(matches.first)
        XCTAssertEqual(match.source, .musicbrainz)
        XCTAssertEqual(match.title, "Kind of Blue")
        XCTAssertEqual(match.artistDisplay, "Miles Davis")
        XCTAssertEqual(match.year, 1959)
        XCTAssertEqual(match.country, "US")
        XCTAssertEqual(match.labels.first?.name, "Columbia")
        XCTAssertEqual(match.labels.first?.catalogNumber, "CL 1355")
        XCTAssertEqual(match.musicbrainzMBID, "1e5dfa7e-6e2c-4a1b-9c7d-000000000000")
        XCTAssertEqual(match.tracks.map(\.title), ["So What"])
        XCTAssertEqual(match.tracks.first?.durationSeconds, 562) // 562000 ms
        XCTAssertEqual(
            match.coverImageURL?.absoluteString,
            "https://coverartarchive.org/release/1e5dfa7e-6e2c-4a1b-9c7d-000000000000/front"
        )
    }

    func testYearParsing() {
        XCTAssertEqual(MusicBrainzClient.parseYear("1959-08-17"), 1959)
        XCTAssertEqual(MusicBrainzClient.parseYear("1990"), 1990)
        XCTAssertNil(MusicBrainzClient.parseYear("59"))
        XCTAssertNil(MusicBrainzClient.parseYear(nil))
    }
}
