import XCTest
@testable import VinylCore

final class DiscogsClientTests: XCTestCase {
    private func client(_ handler: @escaping @Sendable (URL) -> Data) -> DiscogsClient {
        DiscogsClient(token: "test-token", http: StubHTTPClient(handler), limiter: RateLimiter(minInterval: 0))
    }

    func testSearchByBarcodeParsesCandidate() async throws {
        let search = try Fixture.data("discogs_search")
        let results = try await client { _ in search }.searchByBarcode("888880000001")

        XCTAssertEqual(results.count, 1)
        let match = try XCTUnwrap(results.first)
        XCTAssertEqual(match.source, .discogs)
        XCTAssertEqual(match.artistDisplay, "Miles Davis")
        XCTAssertEqual(match.title, "Kind Of Blue")
        XCTAssertEqual(match.year, 1959)
        XCTAssertEqual(match.country, "US")
        XCTAssertEqual(match.format, "LP")
        XCTAssertEqual(match.discogsReleaseID, 249504)
        XCTAssertEqual(match.labels.first?.name, "Columbia")
        XCTAssertEqual(match.labels.first?.catalogNumber, "CS 8163")
        XCTAssertEqual(match.styles, ["Modal", "Hard Bop"])
        XCTAssertEqual(match.coverImageURL?.absoluteString, "https://img.discogs.com/cover.jpg")
        XCTAssertTrue(match.tracks.isEmpty, "search results carry no tracklist yet")
    }

    func testEnrichAddsTracklistSpeedAndHiResCover() async throws {
        let search = try Fixture.data("discogs_search")
        let release = try Fixture.data("discogs_release")
        let discogs = client { url in
            url.path.contains("/releases/") ? release : search
        }

        let candidate = try await discogs.searchByBarcode("888880000001")[0]
        let enriched = try await discogs.enrich(candidate)

        XCTAssertEqual(enriched.tracks.map(\.title), ["So What", "Freddie Freeloader"])
        XCTAssertEqual(enriched.tracks.first?.durationSeconds, 562) // 9:22
        XCTAssertEqual(enriched.speed, "45 RPM")
        XCTAssertEqual(enriched.coverImageURL?.absoluteString, "https://img.discogs.com/front-hires.jpg")
    }

    func testDurationParsing() {
        XCTAssertEqual(DiscogsClient.parseDuration("9:22"), 562)
        XCTAssertEqual(DiscogsClient.parseDuration("1:02:03"), 3723)
        XCTAssertNil(DiscogsClient.parseDuration(""))
        XCTAssertNil(DiscogsClient.parseDuration("abc"))
    }

    func testArtistDisambiguationSuffixIsStripped() {
        XCTAssertEqual(DiscogsClient.cleanArtistNames(["Nirvana (2)", "Miles Davis"]), ["Nirvana", "Miles Davis"])
    }
}
