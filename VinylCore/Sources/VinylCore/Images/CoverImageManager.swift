import Foundation
#if canImport(ImageIO)
import ImageIO
import UniformTypeIdentifiers
#endif

/// Downloads cover art into the library's `Covers/` folder and, on Apple
/// platforms, writes a downsampled thumbnail alongside it. Returns paths
/// relative to the library folder so they can be stored in the database and
/// resolved by any app that opens the library.
public struct CoverImageManager {
    /// A cover that won't fit in a record sleeve won't fit here either. Remote
    /// art is untrusted input; refuse an implausible one rather than buffer it.
    public static let maxCoverBytes = 24 * 1024 * 1024

    public enum CoverError: Error, Equatable {
        case tooLarge(bytes: Int)
    }

    private let http: HTTPClient
    private let fileManager: FileManager
    private let thumbnailMaxPixel: Int

    public init(
        http: HTTPClient = URLSessionHTTPClient(),
        fileManager: FileManager = .default,
        thumbnailMaxPixel: Int = 400
    ) {
        self.http = http
        self.fileManager = fileManager
        self.thumbnailMaxPixel = thumbnailMaxPixel
    }

    /// Downloads `url` into `<libraryFolder>/Covers/<releaseID>.<ext>` and, when
    /// possible, a `<releaseID>_thumb.jpg`. Returns the relative paths.
    @discardableResult
    public func downloadCover(
        from url: URL,
        releaseID: String,
        into libraryFolder: URL
    ) async throws -> (coverPath: String, thumbPath: String?) {
        let data = try await http.data(from: url, headers: [:])
        guard data.count <= Self.maxCoverBytes else { throw CoverError.tooLarge(bytes: data.count) }

        let coversDirectory = libraryFolder.appendingPathComponent("Covers", isDirectory: true)
        try fileManager.createDirectory(at: coversDirectory, withIntermediateDirectories: true)

        // The id can come from an imported library and the extension from a
        // remote URL — neither is ours, so neither gets to shape a path.
        let name = SafeFilename.component(releaseID, fallback: UUID().uuidString)
        let ext = SafeFilename.fileExtension(url.pathExtension, fallback: "jpg")

        let coverFile = coversDirectory.appendingPathComponent("\(name).\(ext)")
        try data.write(to: coverFile)
        let coverPath = "Covers/\(name).\(ext)"

        var thumbPath: String?
        if let thumbnailData = Self.downsampledJPEG(from: data, maxPixel: thumbnailMaxPixel) {
            let thumbFile = coversDirectory.appendingPathComponent("\(name)_thumb.jpg")
            try thumbnailData.write(to: thumbFile)
            thumbPath = "Covers/\(name)_thumb.jpg"
        }

        return (coverPath, thumbPath)
    }

    /// Produces a JPEG thumbnail bounded by `maxPixel` on its longest edge.
    /// Returns nil on platforms without ImageIO or when the data isn't a
    /// decodable image.
    static func downsampledJPEG(from data: Data, maxPixel: Int) -> Data? {
        #if canImport(ImageIO)
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        let outputData = NSMutableData()
        let type = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(outputData, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return outputData as Data
        #else
        return nil
        #endif
    }
}
