import Foundation
import VinylCore

/// Produces shareable copies of the library: either the SQLite database on its
/// own, or a zip of the database plus the cover images.
///
/// Files are written to the temporary directory and handed to the iOS share
/// sheet; iOS reclaims that directory on its own, and each run clears the
/// previous export first.
enum LibraryExporter {
    /// A file ready to share. `Identifiable` so it can drive `.sheet(item:)`.
    struct ExportFile: Identifiable, Equatable {
        let url: URL
        var id: String { url.path }
        var name: String { url.lastPathComponent }
    }

    enum Format {
        /// Just `Library.sqlite` — opens in any SQLite tool, no cover images.
        case database
        /// Database + `Covers/`, zipped — a complete, restorable snapshot.
        case archive
    }

    enum ExportError: LocalizedError {
        case archiveFailed

        var errorDescription: String? {
            switch self {
            case .archiveFailed: return "Couldn't package the library for sharing."
            }
        }
    }

    private static let exportDirectoryName = "PacificRecordExport"

    /// Builds the export off the main thread and returns the file to share.
    static func export(
        _ format: Format,
        store: LibraryStore,
        libraryFolder: URL
    ) async throws -> ExportFile {
        try await Task.detached(priority: .userInitiated) { () async throws -> ExportFile in
            let workspace = try freshWorkspace()
            let stamp = timestamp()

            switch format {
            case .database:
                let file = workspace.appendingPathComponent("Pacific Record \(stamp).sqlite")
                try store.exportDatabase(to: file)
                return ExportFile(url: file)

            case .archive:
                // Stage a folder, then let NSFileCoordinator zip it — the
                // directory name becomes the folder inside the archive.
                let staging = workspace.appendingPathComponent("Pacific Record \(stamp)", isDirectory: true)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                try store.exportDatabase(to: staging.appendingPathComponent("Library.sqlite"))
                copyCovers(from: libraryFolder, into: staging)
                let zip = try zipDirectory(staging, into: workspace)
                try? FileManager.default.removeItem(at: staging)
                return ExportFile(url: zip)
            }
        }.value
    }

    // MARK: - Internals

    /// A clean export directory, so old exports don't accumulate or get shared
    /// by mistake.
    private static func freshWorkspace() throws -> URL {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(exportDirectoryName, isDirectory: true)
        try? FileManager.default.removeItem(at: workspace)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return workspace
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private static func copyCovers(from libraryFolder: URL, into staging: URL) {
        let fileManager = FileManager.default
        let source = libraryFolder.appendingPathComponent("Covers", isDirectory: true)
        guard fileManager.fileExists(atPath: source.path) else { return }
        try? fileManager.copyItem(at: source, to: staging.appendingPathComponent("Covers", isDirectory: true))
    }

    /// Zips a directory using `NSFileCoordinator`'s `.forUploading` option,
    /// which hands back a temporary zip — copied out before the accessor
    /// returns, since the coordinator deletes it afterwards.
    private static func zipDirectory(_ directory: URL, into workspace: URL) throws -> URL {
        let destination = workspace.appendingPathComponent(directory.lastPathComponent + ".zip")
        var coordinatorError: NSError?
        var copyError: Error?

        NSFileCoordinator().coordinate(
            readingItemAt: directory,
            options: [.forUploading],
            error: &coordinatorError
        ) { zippedURL in
            do {
                try FileManager.default.copyItem(at: zippedURL, to: destination)
            } catch {
                copyError = error
            }
        }

        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw ExportError.archiveFailed
        }
        return destination
    }
}
