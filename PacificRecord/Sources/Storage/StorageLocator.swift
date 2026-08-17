import CryptoKit
import Foundation
import VinylCore

enum StorageMode: String, Sendable {
    case iCloud
    case local
}

struct LibraryLocation: Sendable, Equatable {
    let folder: URL
    let mode: StorageMode
}

/// Whether a folder holds a library, and if so whether it can actually be read.
///
/// The middle state is the important one. An iCloud file that hasn't downloaded
/// yet is *not* absent, but `FileManager.fileExists` says it is — the real name
/// isn't on disk, only a hidden `.Library.sqlite.icloud` placeholder. Reading
/// that as "no library here" is how a local database ends up copied over a full
/// cloud one, and how SQLite ends up creating an empty file that then conflicts
/// with the real one when it arrives.
enum LibraryPresence: Sendable, Equatable {
    case none
    case present
    case notDownloaded
}

/// Both sides hold a library and neither has been superseded, so the app can't
/// pick one without guessing.
struct StorageConflict: Sendable, Equatable {
    let cloud: LibraryLocation
    let localFolder: URL
    let cloudRecordCount: Int
    let localRecordCount: Int
}

/// What `resolve` concluded. Only `.ready` may be opened — the other two mean
/// opening the path would create a database that shouldn't exist.
enum StorageResolution: Sendable, Equatable {
    case ready(LibraryLocation)
    case awaitingDownload(LibraryLocation)
    case needsChoice(StorageConflict)
}

/// How the signed-in iCloud account compares with the one the library was last
/// opened under. Without this, "signed out" and "signed into a different Apple
/// Account" both look identical to the user: their records are simply gone.
enum ICloudAccountState: Sendable, Equatable {
    /// Nothing recorded yet — a fresh install.
    case unknown
    case same
    case signedOut
    case changed
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
    private static let accountKey = "iCloudAccountFingerprint"
    /// How long to wait for an iCloud database before handing the decision back
    /// to the user. Small libraries arrive in a second; a first sync on a new
    /// device can take much longer, and stalling the launch screen for that is
    /// worse than saying so.
    private static let downloadWait: TimeInterval = 15

    /// True if the device is signed into iCloud with iCloud Drive available.
    static func iCloudAvailable() async -> Bool {
        await Task.detached(priority: .userInitiated) { iCloudDocumentsFolder() != nil }.value
    }

    static func databaseURL(in folder: URL) -> URL {
        folder.appendingPathComponent(databaseName)
    }

    // MARK: - Resolution

    static func resolve(preferICloud: Bool) async -> StorageResolution {
        await Task.detached(priority: .userInitiated) {
            let local = localFolder()
            ensureFolders(local)
            let cloud = iCloudDocumentsFolder()

            guard preferICloud, let cloud else {
                return .ready(resolveLocal(local, cloud: cloud))
            }
            ensureFolders(cloud)
            let cloudLocation = LibraryLocation(folder: cloud, mode: .iCloud)

            // Settle the cloud side into a state worth comparing *before*
            // comparing it with anything.
            var cloudPresence = presence(in: cloud)
            if cloudPresence == .notDownloaded {
                cloudPresence = downloadDatabase(in: cloud)
            }
            guard cloudPresence != .notDownloaded else {
                return .awaitingDownload(cloudLocation)
            }

            switch (cloudPresence, presence(in: local)) {
            case (.present, .present):
                // Two real libraries. Never guess.
                return .needsChoice(StorageConflict(
                    cloud: cloudLocation,
                    localFolder: local,
                    cloudRecordCount: recordCount(at: databaseURL(in: cloud)),
                    localRecordCount: recordCount(at: databaseURL(in: local))))
            case (.none, .present):
                // First move up to iCloud. Copy, then set the local file aside
                // so it stops looking like a rival library next launch.
                copyLibrary(from: local, to: cloud)
                supersedeLibrary(in: local)
                return .ready(cloudLocation)
            default:
                return .ready(cloudLocation)
            }
        }.value
    }

    /// Local storage chosen, or iCloud unavailable. If this device has no
    /// library of its own but iCloud has one, bring it down first — otherwise
    /// turning iCloud off would open an empty database next to a full one.
    private static func resolveLocal(_ local: URL, cloud: URL?) -> LibraryLocation {
        if presence(in: local) == .none, let cloud, downloadDatabase(in: cloud) == .present {
            copyLibrary(from: cloud, to: local)
        }
        return LibraryLocation(folder: local, mode: .local)
    }

    // MARK: - Presence

    static func presence(in folder: URL) -> LibraryPresence {
        let fileManager = FileManager.default
        let database = databaseURL(in: folder)
        if fileManager.fileExists(atPath: database.path) { return .present }

        // Not on disk under its own name: either genuinely absent, or an
        // undownloaded ubiquitous item sitting behind a placeholder.
        let placeholder = folder.appendingPathComponent(".\(databaseName).icloud")
        if fileManager.fileExists(atPath: placeholder.path) { return .notDownloaded }

        let status = (try? database.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
            .ubiquitousItemDownloadingStatus
        return status == nil ? .none : .notDownloaded
    }

    /// Counts a database's records so a conflict can be described in terms the
    /// user can act on. Opening runs migrations, which is what opening it for
    /// real would do anyway.
    private static func recordCount(at database: URL) -> Int {
        (try? LibraryStore(path: database.path).count()) ?? 0
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

    // MARK: - Moving libraries (copy and rename only, never delete)

    /// Coordinated copy of a database plus its covers, replacing whatever is at
    /// the target. Only called once the caller knows which side should win.
    static func copyLibrary(from source: URL, to target: URL) {
        let fileManager = FileManager.default
        let sourceDB = databaseURL(in: source)
        guard fileManager.fileExists(atPath: sourceDB.path) else { return }
        ensureFolders(target)

        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(readingItemAt: sourceDB, options: [],
                               writingItemAt: databaseURL(in: target), options: .forReplacing,
                               error: &error) { source, destination in
            try? fileManager.removeItem(at: destination)
            try? fileManager.copyItem(at: source, to: destination)
        }
        copyCovers(from: source, to: target)
    }

    /// Renames a database aside rather than deleting it. Once a library has been
    /// adopted by the other side, leaving it under the live name makes it look
    /// like a rival on every subsequent launch — but it's still the user's data,
    /// so it stays on disk under a dated name.
    @discardableResult
    static func supersedeLibrary(in folder: URL) -> URL? {
        let fileManager = FileManager.default
        let database = databaseURL(in: folder)
        guard fileManager.fileExists(atPath: database.path) else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let archived = folder.appendingPathComponent(
            "Superseded \(formatter.string(from: Date())).sqlite")
        try? fileManager.removeItem(at: archived)
        try? fileManager.moveItem(at: database, to: archived)
        return archived
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

    /// Asks iCloud for the database and waits a bounded time, then reports what
    /// the folder actually holds — so the caller decides rather than assumes.
    @discardableResult
    private static func downloadDatabase(in folder: URL) -> LibraryPresence {
        try? FileManager.default.startDownloadingUbiquitousItem(at: databaseURL(in: folder))
        let deadline = Date().addingTimeInterval(downloadWait)
        while Date() < deadline {
            let state = presence(in: folder)
            if state != .notDownloaded { return state }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return presence(in: folder)
    }

    // MARK: - Account identity

    /// A stable fingerprint of the signed-in iCloud account. The token itself is
    /// opaque and only meaningful for equality, so a hash of its archived bytes
    /// is stored rather than the token.
    static func iCloudAccountFingerprint() -> String? {
        guard let token = FileManager.default.ubiquityIdentityToken,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func accountState() -> ICloudAccountState {
        let stored = UserDefaults.standard.string(forKey: accountKey)
        switch (stored, iCloudAccountFingerprint()) {
        case (nil, _): return .unknown
        case let (.some(remembered), .some(current)): return remembered == current ? .same : .changed
        case (.some, nil): return .signedOut
        }
    }

    /// Records the account a successful open happened under. A sign-out leaves
    /// the last known account in place, so signing into a *different* one later
    /// is still detectable.
    static func rememberAccount() {
        guard let current = iCloudAccountFingerprint() else { return }
        UserDefaults.standard.set(current, forKey: accountKey)
    }
}
