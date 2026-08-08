import Foundation
import ImageIO
import UIKit
import VinylCore
import WidgetKit

/// Keeps the widgets' shared snapshot in step with the library.
///
/// Writes a small JSON payload plus downsampled covers for a rotation pool into
/// the App Group container, then asks WidgetKit to reload. Everything runs off
/// the main thread; failures are silent by design — a stale or missing widget
/// snapshot must never disturb the app.
enum WidgetSnapshotWriter {
    /// Covers are drawn at most ~160pt wide in a widget.
    private static let coverPixelSize = 320

    /// Rebuilds the snapshot from the current library.
    static func update(
        records: [Release],
        libraryName: String,
        artistCount: Int,
        genreCount: Int,
        formattedValue: String?,
        valuedCount: Int,
        libraryFolder: URL
    ) {
        // Pick the rotation pool now: a stable random sample, reshuffled
        // whenever the library changes.
        let pool = Array(records.shuffled().prefix(WidgetShared.poolSize))
        let flattened = pool.map { release in
            (id: release.id,
             title: release.title,
             artist: release.artistDisplay,
             year: release.year,
             format: release.format,
             rating: release.rating,
             coverPath: release.listCoverPath)
        }

        Task.detached(priority: .utility) {
            guard let coversURL = WidgetShared.coversURL else { return }
            let fileManager = FileManager.default
            // Start clean so removed records don't leave covers behind.
            try? fileManager.removeItem(at: coversURL)
            try? fileManager.createDirectory(at: coversURL, withIntermediateDirectories: true)

            var widgetRecords: [WidgetRecord] = []
            for record in flattened {
                var coverFile: String?
                if let coverPath = record.coverPath {
                    let source = libraryFolder.appendingPathComponent(coverPath)
                    let name = "\(record.id).jpg"
                    if writeDownsampledCover(from: source, to: coversURL.appendingPathComponent(name)) {
                        coverFile = name
                    }
                }
                widgetRecords.append(WidgetRecord(
                    id: record.id,
                    title: record.title,
                    artist: record.artist,
                    year: record.year,
                    format: record.format,
                    rating: record.rating,
                    coverFile: coverFile
                ))
            }

            let snapshot = WidgetSnapshot(
                generatedAt: Date(),
                libraryName: libraryName,
                recordCount: records.count,
                artistCount: artistCount,
                genreCount: genreCount,
                formattedValue: formattedValue,
                valuedCount: valuedCount,
                records: widgetRecords
            )
            try? WidgetShared.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Writes a small JPEG for the widget to draw. Returns false if there was
    /// no readable image.
    private static func writeDownsampledCover(from source: URL, to destination: URL) -> Bool {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, options) else { return false }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: coverPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions as CFDictionary),
              let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
        else { return false }
        return (try? data.write(to: destination, options: .atomic)) != nil
    }
}
