import Foundation
import ImageIO
import UIKit

/// Loads cover images off the main thread, downsampled to the size they're
/// actually drawn at, and caches the results.
///
/// Without this, every cover in the Library decoded a full-resolution JPEG
/// (Apple artwork is 1500×1500) synchronously inside `body` — repeatedly, since
/// SwiftUI re-evaluates bodies while scrolling. Decoding to the tile size via
/// ImageIO is dramatically cheaper in both CPU and memory.
///
/// `NSCache` is thread-safe, so this is safe to touch from any isolation
/// context and evicts itself under memory pressure.
final class CoverImageLoader: @unchecked Sendable {
    static let shared = CoverImageLoader()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 500
    }

    /// A cached image, if one is already decoded — lets a view show artwork on
    /// its very first frame instead of flashing the placeholder.
    func cached(path: String, maxPixel: Int) -> UIImage? {
        cache.object(forKey: Self.key(path: path, maxPixel: maxPixel))
    }

    /// The decoded image, from cache or freshly decoded off the main thread.
    func image(at url: URL, path: String, maxPixel: Int) async -> UIImage? {
        let key = Self.key(path: path, maxPixel: maxPixel)
        if let hit = cache.object(forKey: key) { return hit }

        let decoded = await Task.detached(priority: .userInitiated) {
            Self.downsample(url: url, maxPixel: maxPixel)
        }.value

        if let decoded { cache.setObject(decoded, forKey: key) }
        return decoded
    }

    // MARK: - Internals

    private static func key(path: String, maxPixel: Int) -> NSString {
        "\(path)@\(maxPixel)" as NSString
    }

    private static func downsample(url: URL, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}

/// Pixel budgets for the places covers are drawn (longest edge, ~3× the point
/// size so they stay sharp on a Retina display).
enum CoverSize {
    static let row = 180
    static let tile = 420
    static let form = 300
    static let detail = 900
    /// Full-screen viewer: enough detail to pinch into without an uncapped decode.
    static let viewer = 2400
}
