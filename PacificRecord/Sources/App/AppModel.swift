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
        /// The iCloud library exists but hasn't downloaded. Opening the path now
        /// would create an empty file that conflicts with the real one.
        case awaitingICloud
        /// This device and iCloud both hold a library; the user picks.
        case chooseLibrary(StorageConflict)
        case failed(String)
    }

    /// Which library survives when both sides have one.
    enum LibraryChoice {
        case keepICloud
        case keepThisDevice
        case merge
    }

    var phase: Phase = .preparing
    var storageMode: StorageMode = .local
    var iCloudAvailable = false
    /// True while a runtime storage switch is in progress (keeps the UI up).
    var switchingStorage = false
    /// How the signed-in iCloud account compares with the last one used.
    private(set) var accountState: ICloudAccountState = .unknown
    /// A one-off explanation shown after launch when storage didn't end up where
    /// the user would expect — the difference between "your records are gone"
    /// and "you're signed out of iCloud".
    var storageNotice: String?
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
            accountState = StorageLocator.accountState()
            apply(await StorageLocator.resolve(preferICloud: prefersICloud && iCloudAvailable))
        }
    }

    /// Runtime switch from Settings. Keeps `phase == .ready` where it can, so
    /// the current screen (and Settings sheet) stay mounted.
    func setPreferICloud(_ prefer: Bool) {
        prefersICloud = prefer
        Task {
            switchingStorage = true
            iCloudAvailable = await StorageLocator.iCloudAvailable()
            apply(await StorageLocator.resolve(preferICloud: prefer && iCloudAvailable))
            switchingStorage = false
        }
    }

    /// Re-runs resolution after the user asks to wait for iCloud again.
    func retryICloud() {
        prepare()
    }

    /// Gives up on the iCloud copy for this launch and works locally. The
    /// preference is left alone, so the next launch tries iCloud again rather
    /// than quietly demoting the user.
    func continueWithoutICloud() {
        phase = .preparing
        Task {
            apply(await StorageLocator.resolve(preferICloud: false))
        }
    }

    // MARK: - Conflict resolution

    func resolveConflict(_ conflict: StorageConflict, choice: LibraryChoice) {
        phase = .preparing
        let cloudFolder = conflict.cloud.folder
        let localFolder = conflict.localFolder

        Task {
            switch choice {
            case .keepICloud:
                // Nothing to copy; just stop the local file looking like a rival.
                await Task.detached { _ = StorageLocator.supersedeLibrary(in: localFolder) }.value

            case .keepThisDevice:
                await Task.detached {
                    StorageLocator.copyLibrary(from: localFolder, to: cloudFolder)
                    StorageLocator.supersedeLibrary(in: localFolder)
                }.value

            case .merge:
                await mergeLocalIntoCloud(localFolder: localFolder, cloudFolder: cloudFolder)
            }
            apply(.ready(conflict.cloud))
        }
    }

    /// Adds everything this device has that iCloud doesn't, leaving the iCloud
    /// copy as the survivor. Records already on both sides keep the iCloud
    /// version — merging can add, never overwrite.
    private func mergeLocalIntoCloud(localFolder: URL, cloudFolder: URL) async {
        guard let cloudStore = try? LibraryStore(path: StorageLocator.databaseURL(in: cloudFolder).path)
        else { return }
        _ = try? await LibraryImporter.mergeLibrary(
            at: StorageLocator.databaseURL(in: localFolder),
            covers: localFolder.appendingPathComponent("Covers", isDirectory: true),
            into: cloudStore,
            libraryFolder: cloudFolder)
        await Task.detached { _ = StorageLocator.supersedeLibrary(in: localFolder) }.value
    }

    // MARK: - Internals

    private func apply(_ resolution: StorageResolution) {
        switch resolution {
        case let .ready(location):
            storageMode = location.mode
            do {
                library = try openLibrary(at: location.folder)
                StorageLocator.rememberAccount()
                storageNotice = notice(for: location)
                phase = .ready
            } catch {
                phase = .failed((error as NSError).localizedDescription)
            }
        case .awaitingDownload:
            phase = .awaitingICloud
        case let .needsChoice(conflict):
            phase = .chooseLibrary(conflict)
        }
    }

    /// Explains a launch that landed on local storage when iCloud was wanted.
    private func notice(for location: LibraryLocation) -> String? {
        guard location.mode == .local, prefersICloud else { return nil }
        switch accountState {
        case .signedOut:
            return "This iPhone is signed out of iCloud, so Pacific Record is using the copy stored on the device. Your iCloud library is still in your account — sign back in to get it back."
        case .changed:
            return "This iPhone is signed into a different iCloud account than the one your library was saved under. Pacific Record is using the copy stored on the device instead."
        case .same, .unknown:
            return nil
        }
    }

    private func openLibrary(at folder: URL) throws -> LibraryModel {
        let store = try LibraryStore(path: StorageLocator.databaseURL(in: folder).path)
        return LibraryModel(store: store, libraryFolder: folder)
    }
}
