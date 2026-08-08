import XCTest
@testable import VinylCore

final class ReleaseMediumTests: XCTestCase {
    func testRecognisesDiscogsFormatNames() {
        XCTAssertEqual(ReleaseMedium.named("Vinyl"), .vinyl)
        XCTAssertEqual(ReleaseMedium.named("Flexi-disc"), .vinyl)
        XCTAssertEqual(ReleaseMedium.named("CD"), .cd)
        XCTAssertEqual(ReleaseMedium.named("CDr"), .cd)
        XCTAssertEqual(ReleaseMedium.named("SACD"), .sacd, "SACD must not read as a plain CD")
        XCTAssertEqual(ReleaseMedium.named("Cassette"), .cassette)
        XCTAssertEqual(ReleaseMedium.named("8-Track Cartridge"), .eightTrack)
        XCTAssertEqual(ReleaseMedium.named("Reel-To-Reel"), .reelToReel)
        XCTAssertEqual(ReleaseMedium.named("Blu-ray"), .bluRay)
        XCTAssertEqual(ReleaseMedium.named("HD DVD"), .bluRay)
        XCTAssertEqual(ReleaseMedium.named("Pathé Disc"), .shellac, "diacritics are folded")
        XCTAssertEqual(ReleaseMedium.named("File"), .file)
    }

    func testRecognisesMusicBrainzQualifiedNames() {
        XCTAssertEqual(ReleaseMedium.named("12\" Vinyl"), .vinyl)
        XCTAssertEqual(ReleaseMedium.named("7\" Vinyl"), .vinyl)
        XCTAssertEqual(ReleaseMedium.named("8cm CD"), .cd)
        XCTAssertEqual(ReleaseMedium.named("Hybrid SACD"), .sacd)
        XCTAssertEqual(ReleaseMedium.named("Digital Media"), .file)
    }

    /// Search results flatten the medium in with pressing descriptions; nothing
    /// in that vocabulary may be mistaken for a medium.
    func testPressingDescriptionsAreNotMedia() {
        for description in ["LP", "Album", "Reissue", "45 RPM", "Stereo", "Mono",
                            "Compilation", "Single", "EP", "180 Gram", "Gatefold",
                            "Limited Edition", "Test Pressing", "12\"", "Box Set"] {
            XCTAssertNil(ReleaseMedium.named(description), "\(description) is not a medium")
        }
    }

    func testFilterKeepsSelectedMediaAndUnknownOnes() {
        let vinyl = MediumFilter(selected: [.vinyl])
        XCTAssertTrue(vinyl.matches(mediums: ["Vinyl", "LP"]))
        XCTAssertFalse(vinyl.matches(mediums: ["CD"]))
        XCTAssertTrue(vinyl.matches(mediums: ["Vinyl", "CD"]), "a mixed box set still counts")
        XCTAssertTrue(vinyl.matches(mediums: ["All Media"]), "unknown media are never hidden")
        XCTAssertTrue(vinyl.matches(mediums: []), "nor are releases with no format data")
    }

    func testEmptyOrCompleteSelectionFiltersNothing() {
        XCTAssertTrue(MediumFilter(selected: []).isUnrestricted)
        XCTAssertTrue(MediumFilter(selected: Set(ReleaseMedium.allCases)).isUnrestricted)
        XCTAssertTrue(MediumFilter(selected: []).matches(mediums: ["CD"]))
        XCTAssertFalse(MediumFilter.default.isUnrestricted)
    }

    func testStorageValueRoundTrips() {
        let filter = MediumFilter(selected: [.cassette, .vinyl])
        XCTAssertEqual(filter.storageValue, "vinyl,cassette", "stored in vocabulary order")
        XCTAssertEqual(MediumFilter(storageValue: filter.storageValue), filter)
        XCTAssertEqual(MediumFilter(storageValue: ""), .all)
        XCTAssertEqual(MediumFilter(storageValue: "vinyl,wax-cylinder"), MediumFilter(selected: [.vinyl]),
                       "unknown entries are dropped, not fatal")
    }

    func testDiscogsSearchFormatOnlyForASingleMedium() {
        XCTAssertEqual(MediumFilter(selected: [.vinyl]).discogsSearchFormat, "Vinyl")
        XCTAssertEqual(MediumFilter(selected: [.eightTrack]).discogsSearchFormat, "8-Track Cartridge")
        XCTAssertNil(MediumFilter(selected: [.vinyl, .cd]).discogsSearchFormat)
        XCTAssertNil(MediumFilter.all.discogsSearchFormat)
    }

    func testSummaries() {
        XCTAssertEqual(MediumFilter.all.summary, "All")
        XCTAssertEqual(MediumFilter(selected: [.vinyl]).summary, "Vinyl")
        XCTAssertEqual(MediumFilter(selected: [.vinyl, .cd]).summary, "Vinyl and CD")
        XCTAssertEqual(MediumFilter(selected: [.vinyl, .cd, .cassette]).summary, "3 media")
        XCTAssertEqual(MediumFilter(selected: [.vinyl, .cd, .cassette]).selectedNamesSentence,
                       "Vinyl, CD and Cassette")
    }

    func testApplyDropsUnwantedMedia() {
        let matches = [
            MetadataMatch(id: "1", source: .discogs, title: "A", artistDisplay: "X", mediums: ["Vinyl"]),
            MetadataMatch(id: "2", source: .discogs, title: "A", artistDisplay: "X", mediums: ["CD"]),
            MetadataMatch(id: "3", source: .discogs, title: "A", artistDisplay: "X"),
        ]
        XCTAssertEqual(MediumFilter(selected: [.vinyl]).apply(to: matches).map(\.id), ["1", "3"])
        XCTAssertEqual(MediumFilter.all.apply(to: matches).map(\.id), ["1", "2", "3"])
    }
}
