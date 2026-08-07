import Foundation

enum StorageMode: String, Sendable {
    case iCloud
    case local
}

struct LibraryLocation: Sendable {
    let folder: URL
    let mode: StorageMode
}

/// Resolves where the library lives — the iCloud Drive ubiquity container when
/// available and preferred, otherwise a local folder in Documents. All the
/// blocking file work (ubiquity lookup, placeholder download, migration copies)
/// runs off the main actor.
enum StorageLocator {
    static let containerIdentifier = "iCloud.ro.sofistic.pacificrecord"
    private static let folderName = "Pacific Record"
    private static let databaseName = "Library.sqlite"
    private static let coversName = "Covers"

    /// True if the device is signed into iCloud with iCloud Drive available.
    static func iCloudAvailable() async -> Bool {
        await Task.detached(priority: .userInitiated) { iCloudDocumentsFolder() != nil }.value
    }

    /// Resolves the library folder, ensuring it exists, seeding it from the
    /// other location if it's empty, and downloading the database if it's an
    /// undownloaded iCloud placeholder.
    static func resolve(preferICloud: Bool) async -> LibraryLocation {
        await Task.detached(priority: .userInitiated) {
            let local = localFolder()
            let cloud = iCloudDocumentsFolder()
            let useICloud = preferICloud && cloud != nil

            let target = useICloud ? cloud! : local
            let mode: StorageMode = useICloud ? .iCloud : .local
            ensureFolders(target)

            // Never lose data on a switch: if the target has no library yet,
            // copy the one from the other location (downloading it first if the
            // source is an iCloud placeholder).
            let other: URL? = useICloud ? local : cloud
            if let other { seedIfEmpty(target: target, from: other) }

            if useICloud { downloadDatabaseIfNeeded(in: target) }
            return LibraryLocation(folder: target, mode: mode)
        }.value
    }

    static func databaseURL(in folder: URL) -> URL {
        folder.appendingPathComponent(databaseName)
    }

    // MARK: - Folders

    private static func localFolder() -> URL {
        let base = (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    private static func iCloudDocumentsFolder() -> URL? {
        // Disabled until the app is signed with a paid Apple Developer team.
        guard AppConfig.iCloudEnabled else { return nil }
        // Must run off the main thread — this performs blocking I/O.
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            return nil
        }
        return container.appendingPathComponent("Documents", isDirectory: true)
    }

    private static func ensureFolders(_ folder: URL) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: folder.appendingPathComponent(coversName, isDirectory: true),
                                         withIntermediateDirectories: true)
    }

    // MARK: - Migration (copy only, never delete)

    private static func seedIfEmpty(target: URL, from source: URL) {
        let fileManager = FileManager.default
        let targetDB = databaseURL(in: target)
        guard !fileManager.fileExists(atPath: targetDB.path) else { return }

        downloadDatabaseIfNeeded(in: source)
        let sourceDB = databaseURL(in: source)
        guard fileManager.fileExists(atPath: sourceDB.path) else { return }

        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(readingItemAt: sourceDB, options: [],
                               writingItemAt: targetDB, options: .forReplacing, error: &error) { src, dst in
            try? fileManager.copyItem(at: src, to: dst)
        }
        copyCovers(from: source, to: target)
    }

    private static func copyCovers(from source: URL, to target: URL) {
        let fileManager = FileManager.default
        let sourceCovers = source.appendingPathComponent(coversName, isDirectory: true)
        let targetCovers = target.appendingPathComponent(coversName, isDirectory: true)
        guard let items = try? fileManager.contentsOfDirectory(at: sourceCovers, includingPropertiesForKeys: nil) else { return }
        for item in items {
            let destination = targetCovers.appendingPathComponent(item.lastPathComponent)
            if !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.copyItem(at: item, to: destination)
            }
        }
    }

    // MARK: - iCloud download

    private static func downloadDatabaseIfNeeded(in folder: URL) {
        let fileManager = FileManager.default
        let database = databaseURL(in: folder)
        let status = (try? database.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
        let placeholder = folder.appendingPathComponent(".\(databaseName).icloud")

        let needsDownload = (status != nil && status != .current) || fileManager.fileExists(atPath: placeholder.path)
        guard needsDownload else { return }

        try? fileManager.startDownloadingUbiquitousItem(at: database)
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let current = (try? database.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
                .ubiquitousItemDownloadingStatus == .current
            if current && fileManager.fileExists(atPath: database.path) { return }
            Thread.sleep(forTimeInterval: 0.4)
        }
    }
}
