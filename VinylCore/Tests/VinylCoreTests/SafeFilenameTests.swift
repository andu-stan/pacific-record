import XCTest
@testable import VinylCore

final class SafeFilenameTests: XCTestCase {
    func testComponentStripsAnythingThatCouldShapeAPath() {
        XCTAssertEqual(SafeFilename.component("../../etc/passwd"), "etcpasswd")
        XCTAssertEqual(SafeFilename.component("/absolute/path"), "absolutepath")
        XCTAssertEqual(SafeFilename.component(".."), "unnamed")
        XCTAssertEqual(SafeFilename.component("."), "unnamed")
        XCTAssertEqual(SafeFilename.component(""), "unnamed")
        XCTAssertEqual(SafeFilename.component("a/b\\c:d"), "abcd")
        XCTAssertEqual(SafeFilename.component("%2e%2e%2f"), "2e2e2f", "percent escapes are just characters")
    }

    func testComponentKeepsRealIdentifiersIntact() {
        let uuid = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"
        XCTAssertEqual(SafeFilename.component(uuid), uuid)
        XCTAssertEqual(SafeFilename.component("wish-\(uuid)"), "wish-\(uuid)")
        XCTAssertEqual(SafeFilename.component("cover_1_thumb"), "cover_1_thumb")
    }

    func testComponentIsBounded() {
        XCTAssertEqual(SafeFilename.component(String(repeating: "a", count: 500)).count, 96)
    }

    func testFileExtensionFallsBackForAnythingOdd() {
        XCTAssertEqual(SafeFilename.fileExtension("JPG", fallback: "jpg"), "jpg")
        XCTAssertEqual(SafeFilename.fileExtension("png", fallback: "jpg"), "png")
        XCTAssertEqual(SafeFilename.fileExtension("", fallback: "jpg"), "jpg")
        XCTAssertEqual(SafeFilename.fileExtension("../../evil", fallback: "jpg"), "jpg",
                       "separators are stripped, and what's left is too long to be an extension")
        XCTAssertEqual(SafeFilename.fileExtension("jpg?x=1", fallback: "png"), "jpgx1")
    }

    func testContainmentResolvesTraversal() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertTrue(SafeFilename.isContained(root.appendingPathComponent("Covers/a.jpg"), in: root))
        XCTAssertFalse(SafeFilename.isContained(root.appendingPathComponent("../escape.jpg"), in: root))
        XCTAssertFalse(SafeFilename.isContained(root.appendingPathComponent("Covers/../../x"), in: root))
        XCTAssertFalse(SafeFilename.isContained(root, in: root), "the directory itself is not a file in it")
    }

    func testResolveRejectsEscapingPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertNotNil(SafeFilename.resolve("Covers/art.jpg", in: root))
        XCTAssertNil(SafeFilename.resolve("../../../../Library/Preferences/x.plist", in: root))
        XCTAssertNil(SafeFilename.resolve("Covers/../../../escape.jpg", in: root))
    }
}
