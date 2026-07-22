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

/// Builds the library store (in the app's Documents folder for now; the iCloud
/// container comes in a later milestone) and seeds the sample library.
@MainActor
enum AppEnvironment {
    static func makeLibraryModel() -> LibraryModel {
        let store = makeStore()
        SampleData.seedIfEmpty(store)
        return LibraryModel(store: store)
    }

    private static func makeStore() -> LibraryStore {
        let fileManager = FileManager.default
        let base = (try? fileManager.url(for: .documentDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: true)) ?? fileManager.temporaryDirectory
        let folder = base.appendingPathComponent("Pacific Record", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            return try LibraryStore(path: folder.appendingPathComponent("Library.sqlite").path)
        } catch {
            let fallback = fileManager.temporaryDirectory
                .appendingPathComponent("Library-\(UUID().uuidString).sqlite").path
            return try! LibraryStore(path: fallback)
        }
    }
}
