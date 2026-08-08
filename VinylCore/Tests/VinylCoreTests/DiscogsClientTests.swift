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
        XCTAssertEqual(match.mediums, ["Vinyl"], "the medium is picked out of the flat format list")
    }

    /// Popular LPs come back as a wall of near-identical entries, so a search
    /// result has to carry everything that tells them apart.
    func testSearchResultCarriesPressingDiscriminators() async throws {
        let search = try Fixture.data("discogs_search")
        let match = try XCTUnwrap(try await client { _ in search }.searchByBarcode("888880000001").first)

        XCTAssertEqual(match.formatDescriptions, ["LP", "Album", "Reissue"],
                       "the medium is carried separately; what's left distinguishes pressings")
        XCTAssertEqual(match.formatText, "180 Gram")
        XCTAssertEqual(match.discCount, 1)
        XCTAssertEqual(match.formatSummary, "LP, Album, Reissue, 180 Gram")
        XCTAssertEqual(match.community?.have, 5231)
        XCTAssertEqual(match.community?.want, 812)
        XCTAssertEqual(match.masterID, 8542)
        XCTAssertEqual(match.barcodes, ["888880000001"])
        XCTAssertTrue(match.carries(barcode: "8 888 8000 0001"), "spacing on the sleeve is not significant")
        XCTAssertFalse(match.carries(barcode: "888880000002"))
        XCTAssertEqual(match.webURL?.absoluteString, "https://www.discogs.com/release/249504")
        XCTAssertEqual(match.allVersionsURL?.absoluteString, "https://www.discogs.com/master/8542")
    }

    func testPressingDetailReadsRunoutPlantAndDate() async throws {
        let release = try Fixture.data("discogs_release")
        let detail = try await client { _ in release }.pressingDetail(releaseID: 249504, currency: "EUR")

        XCTAssertEqual(detail.released, "1959-08-17", "a bare year is dropped — the row already shows it")
        XCTAssertEqual(detail.identifiers.filter { $0.type == "Matrix / Runout" }.map(\.value),
                       ["XSM 47324-1A", "XSM 47325-1B"])
        XCTAssertEqual(detail.identifiers.first { $0.value == "XSM 47324-1A" }?.note, "Side A")
        XCTAssertEqual(detail.credits.map(\.role), ["Pressed By", "Mastered At"])
        XCTAssertEqual(detail.credits.first?.name, "Columbia Records Pressing Plant, Pitman")
        XCTAssertEqual(detail.numForSale, 12)
        XCTAssertEqual(detail.lowestPrice?.amount, 24.99)
        XCTAssertEqual(detail.lowestPrice?.currency, "EUR")
        XCTAssertEqual(detail.imageCount, 2)
        XCTAssertNotNil(detail.notes)
        XCTAssertFalse(detail.isEmpty)
    }

    func testEnrichKeepsSearchDiscriminatorsAndAddsMore() async throws {
        let search = try Fixture.data("discogs_search")
        let release = try Fixture.data("discogs_release")
        let discogs = client { url in url.path.contains("/releases/") ? release : search }

        let enriched = try await discogs.enrich(try await discogs.searchByBarcode("888880000001")[0])
        XCTAssertEqual(enriched.masterID, 8542)
        XCTAssertEqual(enriched.community?.have, 5231)
        XCTAssertEqual(enriched.barcodes, ["888880000001"], "only barcode identifiers, not the runout")
    }

    func testTextSearchNarrowsToASingleSelectedMedium() async throws {
        let search = try Fixture.data("discogs_search")
        let seen = RecordedURL()
        let discogs = DiscogsClient(
            token: "test-token",
            mediums: MediumFilter(selected: [.vinyl]),
            http: StubHTTPClient { url in seen.record(url); return search },
            limiter: RateLimiter(minInterval: 0))

        _ = try await discogs.searchByText("kind of blue")
        XCTAssertEqual(seen.query("format"), "Vinyl")

        // A mixed selection can't be one `format` value, so we filter our side.
        let mixed = DiscogsClient(
            token: "test-token",
            mediums: MediumFilter(selected: [.vinyl, .cassette]),
            http: StubHTTPClient { url in seen.record(url); return search },
            limiter: RateLimiter(minInterval: 0))
        _ = try await mixed.searchByText("kind of blue")
        XCTAssertNil(seen.query("format"))

        // A barcode identifies one physical object — never narrow that.
        _ = try await discogs.searchByBarcode("888880000001")
        XCTAssertNil(seen.query("format"))
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

    func testImagesReturnsEveryReleaseImagePrimaryFirst() async throws {
        let release = try Fixture.data("discogs_release")
        let images = try await client { _ in release }.images(releaseID: 249504)

        XCTAssertEqual(images.count, 2)
        // The fixture lists the secondary (back) first; primary (front) is moved ahead.
        XCTAssertEqual(images.first?.full.absoluteString, "https://img.discogs.com/front-hires.jpg")
        XCTAssertEqual(images.first?.thumbnail?.absoluteString, "https://img.discogs.com/front150.jpg")
        XCTAssertEqual(images.last?.full.absoluteString, "https://img.discogs.com/back.jpg")
        XCTAssertEqual(images.last?.thumbnail?.absoluteString, "https://img.discogs.com/back150.jpg")
    }

    func testCollectionPageMapsEntriesRatingAndCondition() async throws {
        let data = try Fixture.data("discogs_collection")
        let page = try await client { _ in data }
            .collectionPage(username: "someone", page: 1, mediaFieldID: 1, sleeveFieldID: 2)

        XCTAssertEqual(page.totalItems, 2)
        XCTAssertEqual(page.items.count, 2)

        let kob = page.items[0]
        XCTAssertEqual(kob.match.title, "Kind Of Blue")
        XCTAssertEqual(kob.match.artistDisplay, "Miles Davis")
        XCTAssertEqual(kob.match.discogsReleaseID, 249504)
        XCTAssertEqual(kob.match.year, 1959)
        XCTAssertEqual(kob.match.format, "LP")
        XCTAssertEqual(kob.match.speed, "45 RPM")
        XCTAssertEqual(kob.match.labels.first?.catalogNumber, "CS 8163")
        XCTAssertEqual(kob.match.coverImageURL?.absoluteString, "https://img.discogs.com/kob.jpg")
        XCTAssertEqual(kob.rating, 5)
        XCTAssertEqual(kob.mediaCondition, .nearMint)   // mapped from the custom field
        XCTAssertEqual(kob.sleeveCondition, .veryGoodPlus)

        let bt = page.items[1]
        XCTAssertEqual(bt.rating, 0)
        XCTAssertNil(bt.mediaCondition)                 // no notes → blank
    }

    func testAddToCollectionParsesInstanceID() async throws {
        let json = Data(#"{"instance_id": 999, "resource_url": "x"}"#.utf8)
        let id = try await client { _ in json }.addToCollection(username: "u", releaseID: 249504)
        XCTAssertEqual(id, 999)
    }

    func testCollectionContainsReflectsItemCount() async throws {
        let present = Data(#"{"pagination":{"page":1,"pages":1,"items":1},"releases":[{"instance_id":1}]}"#.utf8)
        let absent = Data(#"{"pagination":{"page":1,"pages":1,"items":0},"releases":[]}"#.utf8)
        let has = try await client { _ in present }.collectionContains(username: "u", releaseID: 1)
        let hasNot = try await client { _ in absent }.collectionContains(username: "u", releaseID: 1)
        XCTAssertTrue(has)
        XCTAssertFalse(hasNot)
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

    func testPriceSuggestionsParsing() async throws {
        let data = try Fixture.data("discogs_price_suggestions")
        let suggestions = try await client { _ in data }.priceSuggestions(releaseID: 249504)

        XCTAssertEqual(suggestions.count, 8)
        XCTAssertEqual(suggestions[.nearMint]?.amount, 42.0)
        XCTAssertEqual(suggestions[.nearMint]?.currency, "USD")
        XCTAssertEqual(suggestions[.veryGoodPlus]?.amount, 30.0)
        XCTAssertEqual(suggestions[.mint]?.amount, 60.0)
    }

    func testLowestListingPrice() async throws {
        let release = try Fixture.data("discogs_release")
        let money = try await client { _ in release }.lowestListingPrice(releaseID: 249504)
        XCTAssertEqual(money?.amount, 24.99)
        XCTAssertEqual(money?.currency, "USD")
    }

    func testConditionFromDiscogsPriceKey() {
        XCTAssertEqual(Condition(discogsPriceKey: "Near Mint (NM or M-)"), .nearMint)
        XCTAssertEqual(Condition(discogsPriceKey: "Mint (M)"), .mint)
        XCTAssertEqual(Condition(discogsPriceKey: "Very Good Plus (VG+)"), .veryGoodPlus)
        XCTAssertEqual(Condition(discogsPriceKey: "Very Good (VG)"), .veryGood)
        XCTAssertEqual(Condition(discogsPriceKey: "Good Plus (G+)"), .goodPlus)
        XCTAssertEqual(Condition(discogsPriceKey: "Good (G)"), .good)
        XCTAssertNil(Condition(discogsPriceKey: "Sealed"))
    }
}
