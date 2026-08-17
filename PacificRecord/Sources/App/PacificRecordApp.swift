import SwiftUI

@main
struct PacificRecordApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Palette.tint)
                .task { app.prepare() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var showOnboarding = false

    var body: some View {
        phaseContent
            // Explains a launch that landed on local storage when iCloud was
            // wanted — the alternative is a library that looks emptied.
            .alert("Not using iCloud right now", isPresented: noticeShown) {
                Button("OK", role: .cancel) { app.storageNotice = nil }
            } message: {
                Text(app.storageNotice ?? "")
            }
    }

    @ViewBuilder private var phaseContent: some View {
        switch app.phase {
        case .preparing:
            LaunchView()
        case .awaitingICloud:
            ICloudDownloadingView(
                onRetry: { app.retryICloud() },
                onUseLocal: { app.continueWithoutICloud() })
        case let .chooseLibrary(conflict):
            LibraryChoiceView(conflict: conflict) { choice in
                app.resolveConflict(conflict, choice: choice)
            }
        case let .failed(message):
            StorageErrorView(message: message) { app.prepare() }
        case .ready:
            if let library = app.library {
                TabHost()
                    .environment(library)
                    .environment(library.wishlist)
                    .environment(\.libraryFolderURL, library.libraryFolder)
                    .onAppear { if !didOnboard { showOnboarding = true } }
                    .fullScreenCover(isPresented: $showOnboarding) {
                        SetupWizardView {
                            didOnboard = true
                            showOnboarding = false
                        }
                        .environment(library)
                        .environment(app)
                        .environment(\.libraryFolderURL, library.libraryFolder)
                    }
            }
        }
    }

    private var noticeShown: Binding<Bool> {
        Binding(get: { app.storageNotice != nil },
                set: { if !$0 { app.storageNotice = nil } })
    }
}
