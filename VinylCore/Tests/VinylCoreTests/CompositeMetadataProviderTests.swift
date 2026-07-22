import XCTest
@testable import VinylCore

final class CompositeMetadataProviderTests: XCTestCase {
    /// A canned provider for exercising composite routing without networking.
    private struct FakeProvider: MetadataProvider {
        let source: MetadataSource
        var results: [MetadataMatch] = []
        var enrichMarker: String?

        func searchByBarcode(_ barcode: String) async throws -> [MetadataMatch] { results }
        func searchByText(_ query: String) async throws -> [MetadataMatch] { results }
        func enrich(_ match: MetadataMatch) async throws -> MetadataMatch {
            var enriched = match
            if let marker = enrichMarker { enriched.notesMarker = marker }
            return enriched
        }
    }

    private func match(source: MetadataSource) -> MetadataMatch {
        MetadataMatch(
            id: "\(source.rawValue):1",
            source: source,
            title: "Title",
            artistDisplay: "Artist",
            discogsReleaseID: source == .discogs ? 1 : nil,
            musicbrainzMBID: source == .musicbrainz ? "mbid" : nil
        )
    }

    func testFallsBackToSecondProviderWhenFirstIsEmpty() async throws {
        let composite = CompositeMetadataProvider(providers: [
            FakeProvider(source: .discogs, results: []),
            FakeProvider(source: .musicbrainz, results: [match(source: .musicbrainz)]),
        ])
        let results = try await composite.searchByBarcode("x")
        XCTAssertEqual(results.map(\.source), [.musicbrainz])
    }

    func testPrefersFirstProviderWhenItHasResults() async throws {
        let composite = CompositeMetadataProvider(providers: [
            FakeProvider(source: .discogs, results: [match(source: .discogs)]),
            FakeProvider(source: .musicbrainz, results: [match(source: .musicbrainz)]),
        ])
        let results = try await composite.searchByBarcode("x")
        XCTAssertEqual(results.map(\.source), [.discogs])
    }

    func testEnrichRoutesToMatchingSource() async throws {
        let composite = CompositeMetadataProvider(providers: [
            FakeProvider(source: .discogs, enrichMarker: "from-discogs"),
            FakeProvider(source: .musicbrainz, enrichMarker: "from-musicbrainz"),
        ])
        let enriched = try await composite.enrich(match(source: .musicbrainz))
        XCTAssertEqual(enriched.notesMarker, "from-musicbrainz")
    }
}

// Small test-only affordance so the fake can prove which provider enriched.
private extension MetadataMatch {
    var notesMarker: String? {
        get { genre }
        set { genre = newValue }
    }
}
