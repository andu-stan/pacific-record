import SwiftUI

/// Shown while storage is being resolved (e.g. downloading the library from
/// iCloud on a fresh device).
struct LaunchView: View {
    var body: some View {
        ZStack {
            // Matches the native launch screen (Info.plist UILaunchScreen), so
            // the hand-off from the OS launch image is seamless: same background,
            // same centered logo — the spinner and text just fade in below.
            Palette.background.ignoresSafeArea()
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
            VStack {
                Spacer()
                ProgressView()
                    .controlSize(.regular)
                    .tint(Palette.accent)
                Text("Preparing your library…")
                    .font(.prBody)
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 14)
            }
            .padding(.bottom, 48)
        }
    }
}

/// Shown if the library database can't be opened.
struct StorageErrorView: View {
    let message: String
    var onRetry: () -> Void

    var body: some View {
        MessageStateView(
            systemImage: "externaldrive.badge.exclamationmark",
            iconColor: Palette.danger,
            title: "Couldn't open your library",
            message: message,
            primaryTitle: "Try again",
            primaryAction: onRetry
        )
    }
}

/// The small vinyl logo used on launch and onboarding.
struct VinylMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xE8833A), Color(hex: 0xC1440E)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 78, height: 78)
                .shadow(color: Palette.accent.opacity(0.4), radius: 20, y: 12)
            Circle().fill(.black).frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(.white, lineWidth: 5))
                .overlay(Circle().fill(.black).frame(width: 8, height: 8))
        }
    }
}
