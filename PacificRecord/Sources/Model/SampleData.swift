import Foundation
import VinylCore

/// The starter library shown in the design — used to seed a fresh database so
/// the app looks populated on first launch (and matches the mockups).
enum SampleData {
    static func seedIfEmpty(_ store: LibraryStore) {
        guard (try? store.allReleases().isEmpty) ?? true else { return }
        for detail in details {
            store.saveIgnoringErrors(detail)
        }
    }

    private static func release(
        _ title: String,
        _ artist: String,
        year: Int,
        media: Condition,
        rating: Int,
        genre: String,
        styles: [String] = [],
        format: String = "LP",
        speed: String = "33⅓"
    ) -> Release {
        Release(
            id: UUID().uuidString,
            title: title,
            artistDisplay: artist,
            year: year,
            country: "US",
            genre: genre,
            styles: styles,
            format: format,
            speed: speed,
            mediaCondition: media,
            sleeveCondition: media,
            rating: rating
        )
    }

    static var details: [RecordDetail] {
        var list: [RecordDetail] = []

        // Featured record with full metadata + tracklist (the detail mockup).
        let kobID = UUID().uuidString
        let kob = Release(
            id: kobID,
            title: "Kind of Blue",
            artistDisplay: "Miles Davis",
            year: 1959,
            country: "US",
            genre: "Jazz",
            styles: ["Modal"],
            format: "LP",
            speed: "33⅓",
            mediaCondition: .nearMint,
            sleeveCondition: .veryGoodPlus,
            rating: 5,
            notes: "Original six-eye pressing, side 1 mislabeled at correct speed. Found at Amoeba, Jan 2023."
        )
        let kobTracks: [(String, String, Int)] = [
            ("A1", "So What", 562), ("A2", "Freddie Freeloader", 586), ("A3", "Blue in Green", 337),
            ("B1", "All Blues", 693), ("B2", "Flamenco Sketches", 566),
        ]
        list.append(RecordDetail(
            release: kob,
            artists: [Artist(id: UUID().uuidString, name: "Miles Davis", sortName: "Davis, Miles")],
            labels: [LabelCredit(name: "Columbia", catalogNumber: "CS 8163")],
            tracks: kobTracks.enumerated().map { index, t in
                Track(id: UUID().uuidString, releaseID: kobID, position: t.0,
                      side: String(t.0.prefix(1)), title: t.1, durationSeconds: t.2, trackIndex: index)
            }
        ))

        let others: [Release] = [
            release("A Love Supreme", "John Coltrane", year: 1965, media: .veryGoodPlus, rating: 5, genre: "Jazz", styles: ["Free Jazz"]),
            release("Rumours", "Fleetwood Mac", year: 1977, media: .nearMint, rating: 4, genre: "Rock", styles: ["Soft Rock"]),
            release("To Pimp a Butterfly", "Kendrick Lamar", year: 2015, media: .mint, rating: 5, genre: "Hip-Hop", styles: ["Conscious"]),
            release("Random Access Memories", "Daft Punk", year: 2013, media: .nearMint, rating: 5, genre: "Electronic", styles: ["Disco"], format: "2×LP"),
            release("The Velvet Underground & Nico", "The Velvet Underground & Nico", year: 1967, media: .veryGood, rating: 4, genre: "Rock", styles: ["Art Rock"]),
            release("OK Computer", "Radiohead", year: 1997, media: .nearMint, rating: 5, genre: "Rock", styles: ["Alt Rock"]),
            release("What's Going On", "Marvin Gaye", year: 1971, media: .veryGoodPlus, rating: 4, genre: "Soul", styles: ["Funk"]),
            release("Remain in Light", "Talking Heads", year: 1980, media: .veryGoodPlus, rating: 4, genre: "New Wave", styles: ["Post-Punk"]),
            release("Pastel Blues", "Nina Simone", year: 1965, media: .veryGood, rating: 3, genre: "Jazz", styles: ["Vocal"]),
            release("Selected Ambient Works 85–92", "Aphex Twin", year: 1992, media: .veryGoodPlus, rating: 4, genre: "Electronic", styles: ["Ambient"], format: "2×LP"),
            release("Dummy", "Portishead", year: 1994, media: .nearMint, rating: 4, genre: "Electronic", styles: ["Trip Hop"]),
        ]
        for r in others {
            list.append(RecordDetail(
                release: r,
                artists: [Artist(id: UUID().uuidString, name: r.artistDisplay)],
                labels: [],
                tracks: []
            ))
        }
        return list
    }
}

private extension LibraryStore {
    func saveIgnoringErrors(_ detail: RecordDetail) {
        try? save(detail)
    }
}
