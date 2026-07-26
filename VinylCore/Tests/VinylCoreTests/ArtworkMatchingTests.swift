import XCTest
@testable import VinylCore

final class ArtworkMatchingTests: XCTestCase {
    // MARK: Normalization

    func testNormalizeStripsEditionQualifiersAndPunctuation() {
        let plain = ArtworkMatching.normalize("...And Justice for All")
        XCTAssertEqual(plain, "andjusticeforall")
        // The qualifiers that shouldn't change which album this is.
        XCTAssertEqual(ArtworkMatching.normalize("...And Justice for All (Remastered)"), plain)
        XCTAssertEqual(ArtworkMatching.normalize("…And Justice for All [Deluxe Edition]"), plain)
        XCTAssertEqual(ArtworkMatching.normalize("And Justice for All - Remastered 2018"), plain)
    }

    func testNormalizeFoldsDiacriticsAndAmpersand() {
        XCTAssertEqual(ArtworkMatching.normalize("Björk"), "bjork")
        XCTAssertEqual(ArtworkMatching.normalize("Simon & Garfunkel"),
                       ArtworkMatching.normalize("Simon and Garfunkel"))
    }

    func testNormalizeStripsMultiWordEditionTags() {
        XCTAssertEqual(ArtworkMatching.normalize("Abbey Road (Super Deluxe Edition)"),
                       ArtworkMatching.normalize("Abbey Road"))
        XCTAssertEqual(ArtworkMatching.normalize("Purple Rain (Original Motion Picture Soundtrack)"),
                       ArtworkMatching.normalize("Purple Rain"))
    }

    func testNormalizeKeepsMeaningfulParentheticals() {
        // "(Live at Leeds)" carries meaning beyond an edition tag, so the words
        // survive — a bare "(Remastered)" does not.
        XCTAssertTrue(ArtworkMatching.normalize("Something (Live at Leeds)").contains("leeds"))
    }

    /// A live album must not borrow the studio album's cover.
    func testLiveAlbumIsNotConfusedWithStudioAlbum() {
        let albums = [Album(title: "Something (Live at Leeds)", artist: "Some Band")]
        XCTAssertNil(best(albums, title: "Something", artist: "Some Band"))
    }

    func testMatchesAcrossDeluxeEditionSuffix() {
        let albums = [Album(title: "Sgt. Pepper's Lonely Hearts Club Band (Super Deluxe)", artist: "The Beatles")]
        XCTAssertNotNil(best(albums, title: "Sgt. Pepper's Lonely Hearts Club Band", artist: "The Beatles"))
    }

    // MARK: Matching

    private struct Album {
        let title: String
        let artist: String
    }

    private func best(_ albums: [Album], title: String, artist: String) -> Album? {
        ArtworkMatching.bestMatch(
            in: albums, title: title, artist: artist,
            titleOf: { $0.title }, artistOf: { $0.artist }
        )
    }

    /// The regression that motivated this: a matching *artist* alone used to be
    /// enough, so any Metallica album could be returned for any Metallica query.
    func testArtistMatchAloneIsNeverEnough() {
        let albums = [
            Album(title: "Metallica", artist: "Metallica"),
            Album(title: "Master of Puppets", artist: "Metallica"),
        ]
        XCTAssertNil(best(albums, title: "...And Justice for All", artist: "Metallica"))
    }

    func testPicksTheRightAlbumAmongSameArtist() {
        let albums = [
            Album(title: "Metallica", artist: "Metallica"),
            Album(title: "...And Justice for All (Remastered)", artist: "Metallica"),
            Album(title: "Master of Puppets", artist: "Metallica"),
        ]
        let match = best(albums, title: "...And Justice for All", artist: "Metallica")
        XCTAssertEqual(match?.title, "...And Justice for All (Remastered)")
    }

    func testRejectsRightTitleByWrongArtist() {
        let albums = [Album(title: "Plays Metallica by Four Cellos", artist: "Apocalyptica")]
        XCTAssertNil(best(albums, title: "Master of Puppets", artist: "Metallica"))
    }

    func testMatchesDespiteMinorTypoAndPunctuation() {
        let albums = [Album(title: "The Dark Side of the Moon", artist: "Pink Floyd")]
        XCTAssertNotNil(best(albums, title: "Dark Side of the Moon", artist: "Pink Floyd"))
    }

    func testEmptyTitleNeverMatches() {
        let albums = [Album(title: "Metallica", artist: "Metallica")]
        XCTAssertNil(best(albums, title: "", artist: "Metallica"))
    }

    func testSimilarityBounds() {
        XCTAssertEqual(ArtworkMatching.similarity("abc", "abc"), 1)
        XCTAssertEqual(ArtworkMatching.similarity("abc", ""), 0)
        XCTAssertLessThan(ArtworkMatching.similarity("metallica", "andjusticeforall"), 0.5)
    }
}
