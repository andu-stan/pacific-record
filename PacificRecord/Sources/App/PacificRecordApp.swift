import SwiftUI
import Foundation
import VinylCore

@main
struct PacificRecordApp: App {
    @State private var model = AppEnvironment.makeLibraryModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.libraryFolderURL, model.libraryFolder)
                .tint(Palette.tint)
        }
    }
}

struct RootView: View {
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var showOnboarding = false

    var body: some View {
        LibraryView()
            .onAppear {
                if !didOnboard { showOnboarding = true }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    didOnboard = true
                    showOnboarding = false
                }
            }
    }
}

/// Builds the library store in the app's Documents folder (the iCloud container
/// comes in a later milestone) and hands back the model. The library starts
/// empty — records are added by scanning, searching, or manual entry.
@MainActor
enum AppEnvironment {
    static func makeLibraryModel() -> LibraryModel {
        let (store, folder) = makeStore()
        return LibraryModel(store: store, libraryFolder: folder)
    }

    private static func makeStore() -> (LibraryStore, URL) {
        let fileManager = FileManager.default
        let base = (try? fileManager.url(for: .documentDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: true)) ?? fileManager.temporaryDirectory
        let folder = base.appendingPathComponent("Pacific Record", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let store = try LibraryStore(path: folder.appendingPathComponent("Library.sqlite").path)
            return (store, folder)
        } catch {
            let fallback = fileManager.temporaryDirectory
                .appendingPathComponent("PacificRecord-\(UUID().uuidString)", isDirectory: true)
            try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
            let store = try! LibraryStore(path: fallback.appendingPathComponent("Library.sqlite").path)
            return (store, fallback)
        }
    }
}
