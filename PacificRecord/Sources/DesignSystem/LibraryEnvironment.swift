import SwiftUI

private struct LibraryFolderKey: EnvironmentKey {
    static let defaultValue: URL? = nil
}

extension EnvironmentValues {
    /// Folder that stores the library database and its `Covers/` directory, so
    /// views can resolve a record's relative `coverPath` to a file on disk.
    var libraryFolderURL: URL? {
        get { self[LibraryFolderKey.self] }
        set { self[LibraryFolderKey.self] = newValue }
    }
}
