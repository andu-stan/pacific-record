import XCTest
@testable import VinylCore

final class MetadataMatchTests: XCTestCase {
    private func match(
        format: String? = nil,
        descriptions: [String] = [],
        text: String? = nil,
        discCount: Int? = nil,
        barcodes: [String] = []
    ) -> MetadataMatch {
        MetadataMatch(
            id: "discogs:1", source: .discogs, title: "A", artistDisplay: "X",
            format: format, formatDescriptions: descriptions, formatText: text,
            discCount: discCount, barcodes: barcodes, discogsReleaseID: 1)
    }

    func testFormatSummaryLeadsWithDiscCount() {
        XCTAssertEqual(match(descriptions: ["LP", "Album"], discCount: 2).formatSummary, "2×LP, Album")
        XCTAssertEqual(match(descriptions: ["LP", "Album"], discCount: 1).formatSummary, "LP, Album")
        XCTAssertEqual(match(descriptions: ["LP", "Album"]).formatSummary, "LP, Album")
    }

    func testFormatSummaryFallsBackToTheSingleToken() {
        XCTAssertEqual(match(format: "LP").formatSummary, "LP")
        XCTAssertEqual(match(format: "LP", discCount: 3).formatSummary, "3×LP")
        XCTAssertNil(match().formatSummary)
    }

    func testFormatSummaryAppendsFreeTextWithoutRepeatingIt() {
        XCTAssertEqual(match(descriptions: ["LP"], text: "Blue Translucent").formatSummary,
                       "LP, Blue Translucent")
        XCTAssertEqual(match(descriptions: ["LP", "Gatefold"], text: "Gatefold").formatSummary,
                       "LP, Gatefold", "the descriptors already said it")
    }

    func testCarriesBarcodeComparesDigitsOnly() {
        let candidate = match(barcodes: ["7 22975 30302 4", "0-75679-93262-2"])
        XCTAssertTrue(candidate.carries(barcode: "722975303024"))
        XCTAssertTrue(candidate.carries(barcode: "0 75679 93262 2"))
        XCTAssertFalse(candidate.carries(barcode: "722975303025"))
        XCTAssertFalse(candidate.carries(barcode: ""))
        XCTAssertFalse(match().carries(barcode: "722975303024"))
    }

    /// Passing only `barcode` still fills `barcodes`, so an exact-match check
    /// works on matches built the old way (MusicBrainz, manual construction).
    func testSingleBarcodeSeedsTheList() {
        let single = MetadataMatch(id: "mb:1", source: .musicbrainz, title: "A", artistDisplay: "X",
                                   barcode: "722975303024")
        XCTAssertEqual(single.barcodes, ["722975303024"])
        XCTAssertTrue(single.carries(barcode: "7 22975 30302 4"))
    }

    func testWebLinksPerSource() {
        XCTAssertEqual(match().webURL?.absoluteString, "https://www.discogs.com/release/1")
        let mb = MetadataMatch(id: "mb:x", source: .musicbrainz, title: "A", artistDisplay: "X",
                               musicbrainzMBID: "abc-123")
        XCTAssertEqual(mb.webURL?.absoluteString, "https://musicbrainz.org/release/abc-123")
        XCTAssertNil(mb.allVersionsURL, "masters are a Discogs concept")
    }
}
