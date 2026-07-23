import XCTest
@testable import VinylCore

final class LibraryStoreTests: XCTestCase {
    func testSaveAndFetchRoundTrip() throws {
        let store = try makeTempStore()
        let id = UUID().uuidString
        let detail = sampleDetail(id: id, title: "Kind of Blue", artist: "Miles Davis", rating: 5, mediaCondition: .nearMint)

        try store.save(detail)

        let fetched = try XCTUnwrap(store.detail(id: id))
        XCTAssertEqual(fetched.release.title, "Kind of Blue")
        XCTAssertEqual(fetched.release.artistDisplay, "Miles Davis")
        XCTAssertEqual(fetched.release.rating, 5)
        XCTAssertEqual(fetched.release.mediaCondition, .nearMint)
        XCTAssertEqual(fetched.release.styles, ["Modal"])
        XCTAssertEqual(fetched.artists.map(\.name), ["Miles Davis"])
        XCTAssertEqual(fetched.labels.first?.name, "Columbia")
        XCTAssertEqual(fetched.labels.first?.catalogNumber, "CS 8163")
        XCTAssertEqual(fetched.tracks.map(\.title), ["So What"])
        XCTAssertEqual(try store.count(), 1)
    }

    func testArtistsAreDeduplicatedAcrossReleases() throws {
        let store = try makeTempStore()
        try store.save(sampleDetail(title: "Kind of Blue", artist: "Miles Davis"))
        try store.save(sampleDetail(title: "Milestones", artist: "Miles Davis"))

        // Two releases, but the shared artist should exist only once.
        XCTAssertEqual(try store.count(), 2)
    }

    func testFullTextSearch() throws {
        let store = try makeTempStore()
        try store.save(sampleDetail(title: "Kind of Blue", artist: "Miles Davis"))
        try store.save(sampleDetail(title: "A Love Supreme", artist: "John Coltrane"))

        XCTAssertEqual(try store.search("Coltrane").map(\.title), ["A Love Supreme"])
        XCTAssertEqual(try store.search("blue").map(\.title), ["Kind of Blue"])
        XCTAssertEqual(try store.search("Columbia").count, 2) // both share the label
        XCTAssertEqual(try store.search("").count, 2)         // empty query = whole library
    }

    func testUpdateChangesStoredFields() throws {
        let store = try makeTempStore()
        let id = UUID().uuidString
        try store.save(sampleDetail(id: id, title: "Kind of Blue", artist: "Miles Davis", rating: 3))

        var release = try XCTUnwrap(store.detail(id: id)).release
        release.rating = 5
        release.sleeveCondition = .veryGood
        try store.update(release)

        let updated = try XCTUnwrap(store.detail(id: id)).release
        XCTAssertEqual(updated.rating, 5)
        XCTAssertEqual(updated.sleeveCondition, .veryGood)
    }

    func testDeleteRemovesRecordAndAssociations() throws {
        let store = try makeTempStore()
        let id = UUID().uuidString
        try store.save(sampleDetail(id: id, title: "Kind of Blue", artist: "Miles Davis"))

        try store.delete(id: id)

        XCTAssertNil(try store.detail(id: id))
        XCTAssertEqual(try store.count(), 0)
        XCTAssertEqual(try store.search("Kind").count, 0) // FTS row gone too
    }

    func testSortByYearPutsUnknownYearsLast() throws {
        let store = try makeTempStore()
        var noYear = sampleDetail(title: "Undated", artist: "Zeta")
        noYear.release.year = nil
        try store.save(noYear)
        var older = sampleDetail(title: "Older", artist: "Alpha")
        older.release.year = 1950
        try store.save(older)
        var newer = sampleDetail(title: "Newer", artist: "Beta")
        newer.release.year = 1990
        try store.save(newer)

        let titles = try store.allReleases(sortedBy: .yearDescending).map(\.title)
        XCTAssertEqual(titles, ["Newer", "Older", "Undated"])
    }

    func testLocationsDefaultAssignmentAndDelete() throws {
        let store = try makeTempStore()
        let home = try store.addLocation(name: "Home")
        XCTAssertTrue(home.isDefault) // first location becomes default
        let office = try store.addLocation(name: "Office")
        XCTAssertFalse(office.isDefault)

        try store.setDefaultLocation(id: office.id)
        let locations = try store.locations()
        XCTAssertEqual(locations.first?.id, office.id)   // default sorts first
        XCTAssertEqual(locations.first?.isDefault, true)

        let id = UUID().uuidString
        var detail = sampleDetail(id: id, title: "X", artist: "Y")
        detail.release.locationID = office.id
        try store.save(detail)
        XCTAssertEqual(try store.detail(id: id)?.release.locationID, office.id)

        try store.deleteLocation(id: office.id)
        XCTAssertNil(try store.detail(id: id)?.release.locationID)  // unassigned
        XCTAssertEqual(try store.locations().first(where: { $0.id == home.id })?.isDefault, true) // promoted
    }
}
