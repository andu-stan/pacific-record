import Foundation
import Observation
import VinylCore

/// Owns app startup: resolves storage (iCloud vs local), opens the library, and
/// exposes the current `LibraryModel`. Storage can be switched at runtime from
/// Settings without tearing down the UI.
@MainActor
@Observable
final class AppModel {
    enum Phase {
        case preparing
        case ready
        case failed(String)
    }

    var phase: Phase = .preparing
    var storageMode: StorageMode = .local
    var iCloudAvailable = false
    /// True while a runtime storage switch is in progress (keeps the UI up).
    var switchingStorage = false
    private(set) var library: LibraryModel?

    var prefersICloud: Bool {
        get { UserDefaults.standard.object(forKey: "prefersICloud") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "prefersICloud") }
    }

    /// Initial launch resolution — shows the launch screen until the library is
    /// ready.
    func prepare() {
        phase = .preparing
        Task {
            iCloudAvailable = await StorageLocator.iCloudAvailable()
            let location = await StorageLocator.resolve(preferICloud: prefersICloud && iCloudAvailable)
            storageMode = location.mode
            do {
                library = try openLibrary(at: location.folder)
                phase = .ready
            } catch {
                phase = .failed((error as NSError).localizedDescription)
            }
        }
    }

    /// Runtime switch from Settings. Keeps `phase == .ready` so the current
    /// screen (and Settings sheet) stay mounted; shows an inline spinner.
    func setPreferICloud(_ prefer: Bool) {
        prefersICloud = prefer
        Task {
            switchingStorage = true
            iCloudAvailable = await StorageLocator.iCloudAvailable()
            let location = await StorageLocator.resolve(preferICloud: prefer && iCloudAvailable)
            storageMode = location.mode
            if let opened = try? openLibrary(at: location.folder) {
                library = opened
            }
            switchingStorage = false
        }
    }

    private func openLibrary(at folder: URL) throws -> LibraryModel {
        let store = try LibraryStore(path: StorageLocator.databaseURL(in: folder).path)
        return LibraryModel(store: store, libraryFolder: folder)
    }
}
