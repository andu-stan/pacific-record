import Foundation
import XCTest
@testable import VinylCore

/// An `HTTPClient` that returns canned bytes, routed by URL, so metadata
/// clients can be exercised end-to-end without touching the network.
struct StubHTTPClient: HTTPClient {
    let handler: @Sendable (URL) -> Data

    init(_ handler: @escaping @Sendable (URL) -> Data) {
        self.handler = handler
    }

    func data(from url: URL, method: String, body: Data?, headers: [String: String]) async throws -> Data {
        handler(url)
    }
}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "Missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }
}

/// A `LibraryStore` backed by a throwaway temp-directory database.
func makeTempStore() throws -> LibraryStore {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try LibraryStore(path: directory.appendingPathComponent("library.sqlite").path)
}

func sampleDetail(
    id: String = UUID().uuidString,
    title: String,
    artist: String,
    rating: Int = 0,
    mediaCondition: Condition? = nil
) -> RecordDetail {
    let release = Release(
        id: id,
        title: title,
        artistDisplay: artist,
        year: 1959,
        country: "US",
        genre: "Jazz",
        styles: ["Modal"],
        format: "LP",
        speed: "33 1/3",
        barcode: "888",
        mediaCondition: mediaCondition,
        rating: rating
    )
    return RecordDetail(
        release: release,
        artists: [Artist(id: UUID().uuidString, name: artist)],
        labels: [LabelCredit(name: "Columbia", catalogNumber: "CS 8163")],
        tracks: [
            Track(id: UUID().uuidString, releaseID: id, position: "A1", side: "A",
                  title: "So What", durationSeconds: 562, trackIndex: 0),
        ]
    )
}
