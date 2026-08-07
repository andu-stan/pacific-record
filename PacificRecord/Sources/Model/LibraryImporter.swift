import Foundation
import VinylCore

/// Restores a library from a file produced by `LibraryExporter` — either the
/// `.zip` (database + covers) or the bare `.sqlite`.
///
/// The import is done at the *data* level: the backup is opened as a second
/// `LibraryStore` and its records are written through the normal API. Swapping
/// the database file underneath the live connection would be far riskier (the
/// app, and any open sheet, still hold that store), and this way an older
/// backup is migrated to the current schema on the way in.
enum LibraryImporter {
    enum Mode {
        /// Add records the library doesn't already have; keep everything else.
        case merge
        /// Delete the current library, then install the backup.
        case replace
    }

    /// What a picked file contains, shown before the user commits to anything.
    struct Preview: Identifiable, Equatable {
        let id = UUID()
        let fileName: String
        let recordCount: Int
        let locationCount: Int
        let coverCount: Int
        /// Staging area holding the unpacked backup; deleted by `discard`.
        let stagingRoot: URL
        let databaseURL: URL
        let coversURL: URL?

        static func == (lhs: Preview, rhs: Preview) -> Bool { lhs.id == rhs.id }
    }

    struct Summary: Equatable {
        var imported = 0
        var skipped = 0
        var locations = 0
        var covers = 0
        var replaced = false
    }

    enum ImportError: LocalizedError {
        case unreadableFile
        case noDatabaseInArchive
        case notALibrary

        var errorDescription: String? {
            switch self {
            case .unreadableFile:
                return "That file couldn't be opened."
            case .noDatabaseInArchive:
                return "The archive doesn't contain a Pacific Record library."
            case .notALibrary:
                return "That file isn't a Pacific Record library."
            }
        }
    }

    private static let stagingDirectoryName = "PacificRecordImport"

    // MARK: - Inspect

    /// Unpacks the picked file and reports what's inside, without touching the
    /// live library.
    static func prepare(from picked: URL) async throws -> Preview {
        try await Task.detached(priority: .userInitiated) { () async throws -> Preview in
            // Files handed over by the document picker are security-scoped.
            let scoped = picked.startAccessingSecurityScopedResource()
            defer { if scoped { picked.stopAccessingSecurityScopedResource() } }

            let staging = try freshStaging()
            let isZip = picked.pathExtension.lowercased() == "zip"

            if isZip {
                try ZipReader.extract(picked, into: staging)
            } else {
                try FileManager.default.copyItem(
                    at: picked, to: staging.appendingPathComponent("Library.sqlite"))
            }

            guard let databaseURL = findDatabase(in: staging) else {
                throw isZip ? ImportError.noDatabaseInArchive : ImportError.unreadableFile
            }
            let coversURL = findCovers(in: staging)

            // Opening it validates the file; a non-database throws here.
            guard let store = try? LibraryStore(path: databaseURL.path) else {
                throw ImportError.notALibrary
            }
            let records = (try? store.count()) ?? 0
            let locations = (try? store.locations().count) ?? 0
            let covers = coversURL.flatMap {
                try? FileManager.default.contentsOfDirectory(atPath: $0.path).count
            } ?? 0

            return Preview(
                fileName: picked.lastPathComponent,
                recordCount: records,
                locationCount: locations,
                coverCount: covers,
                stagingRoot: staging,
                databaseURL: databaseURL,
                coversURL: coversURL
            )
        }.value
    }

    // MARK: - Apply

    /// Writes the backup into the live library. `progress` is called with 0…1
    /// on the main actor.
    static func apply(
        _ preview: Preview,
        mode: Mode,
        into store: LibraryStore,
        libraryFolder: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Summary {
        let databaseURL = preview.databaseURL
        let coversURL = preview.coversURL

        return try await Task.detached(priority: .userInitiated) { () async throws -> Summary in
            guard let source = try? LibraryStore(path: databaseURL.path) else {
                throw ImportError.notALibrary
            }
            var summary = Summary()
            summary.replaced = (mode == .replace)

            if mode == .replace {
                try store.deleteAllReleases()
                try store.deleteAllLocations()
            }

            // Locations first: records reference them.
            for location in (try? source.locations()) ?? [] {
                try? store.saveLocation(location)
                summary.locations += 1
            }

            let existing = (mode == .merge) ? ((try? store.allReleaseIDs()) ?? []) : []
            let releases = (try? source.allReleases()) ?? []
            let total = max(1, releases.count)

            for (index, release) in releases.enumerated() {
                if mode == .merge, existing.contains(release.id) {
                    summary.skipped += 1
                } else if let detail = try? source.detail(id: release.id) {
                    try? store.save(detail)
                    summary.imported += 1
                }
                // Report periodically rather than per record — a big restore
                // would otherwise hop to the main actor thousands of times.
                if index % 10 == 0 || index == releases.count - 1 {
                    let fraction = Double(index + 1) / Double(total)
                    await MainActor.run { progress(fraction) }
                }
            }

            if let coversURL {
                summary.covers = copyCovers(from: coversURL, into: libraryFolder)
            }
            return summary
        }.value
    }

    /// Removes the staging area. Safe to call more than once.
    static func discard(_ preview: Preview) {
        try? FileManager.default.removeItem(at: preview.stagingRoot)
    }

    // MARK: - Internals

    private static func freshStaging() throws -> URL {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent(stagingDirectoryName, isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        return staging
    }

    /// The archive nests everything under a dated folder, so search rather than
    /// assuming a fixed path.
    private static func findDatabase(in root: URL) -> URL? {
        firstMatch(in: root) { $0.pathExtension.lowercased() == "sqlite" }
    }

    private static func findCovers(in root: URL) -> URL? {
        firstMatch(in: root) { url in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue && url.lastPathComponent == "Covers"
        }
    }

    private static func firstMatch(in root: URL, where matches: (URL) -> Bool) -> URL? {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in walker where matches(url) { return url }
        return nil
    }

    /// Copies cover images alongside the library, never overwriting one that's
    /// already there (paths are content-addressed by record id).
    private static func copyCovers(from source: URL, into libraryFolder: URL) -> Int {
        let fileManager = FileManager.default
        let destination = libraryFolder.appendingPathComponent("Covers", isDirectory: true)
        try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        guard let items = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else {
            return 0
        }
        var copied = 0
        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            if (try? fileManager.copyItem(at: item, to: target)) != nil { copied += 1 }
        }
        return copied
    }
}
