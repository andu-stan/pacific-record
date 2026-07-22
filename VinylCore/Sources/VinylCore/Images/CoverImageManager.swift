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

        let coversDirectory = libraryFolder.appendingPathComponent("Covers", isDirectory: true)
        try fileManager.createDirectory(at: coversDirectory, withIntermediateDirectories: true)

        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        let coverFile = coversDirectory.appendingPathComponent("\(releaseID).\(ext)")
        try data.write(to: coverFile)
        let coverPath = "Covers/\(releaseID).\(ext)"

        var thumbPath: String?
        if let thumbnailData = Self.downsampledJPEG(from: data, maxPixel: thumbnailMaxPixel) {
            let thumbFile = coversDirectory.appendingPathComponent("\(releaseID)_thumb.jpg")
            try thumbnailData.write(to: thumbFile)
            thumbPath = "Covers/\(releaseID)_thumb.jpg"
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
