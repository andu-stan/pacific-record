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
        switch app.phase {
        case .preparing:
            LaunchView()
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
                        OnboardingView {
                            didOnboard = true
                            showOnboarding = false
                        }
                    }
            }
        }
    }
}
