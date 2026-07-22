import XCTest
@testable import VinylCore

final class CoverImageManagerTests: XCTestCase {
    func testDownloadWritesCoverFileAndReturnsRelativePath() async throws {
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]) // JPEG-ish header
        let manager = CoverImageManager(http: StubHTTPClient { _ in bytes })

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let url = try XCTUnwrap(URL(string: "https://img.example.com/cover.jpg"))
        let result = try await manager.downloadCover(from: url, releaseID: "abc123", into: folder)

        XCTAssertEqual(result.coverPath, "Covers/abc123.jpg")
        let written = folder.appendingPathComponent("Covers/abc123.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.path))
        XCTAssertEqual(try Data(contentsOf: written), bytes)
        // Thumbnail generation is best-effort and platform-dependent (ImageIO),
        // so it is intentionally not asserted here.
    }

    func testExtensionlessURLDefaultsToJPG() async throws {
        let manager = CoverImageManager(http: StubHTTPClient { _ in Data([0x1, 0x2]) })
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let url = try XCTUnwrap(URL(string: "https://coverartarchive.org/release/mbid/front"))
        let result = try await manager.downloadCover(from: url, releaseID: "xyz", into: folder)

        XCTAssertEqual(result.coverPath, "Covers/xyz.jpg")
    }
}
