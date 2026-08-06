import SwiftUI
import UIKit

/// Full-screen cover viewer with pinch-to-zoom, pan, and double-tap to toggle.
struct CoverViewer: View {
    let seed: String
    let coverPath: String?

    @Environment(\.libraryFolderURL) private var libraryFolder
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var steadyScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero
    @State private var image: UIImage?

    private let maxScale: CGFloat = 5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            cover
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = min(max(steadyScale * value.magnification, 1), maxScale)
                        }
                        .onEnded { _ in
                            steadyScale = scale
                            if scale <= 1 { resetPosition() }
                        }
                        .simultaneously(with:
                            DragGesture()
                                .onChanged { value in
                                    guard steadyScale > 1 else { return }
                                    offset = CGSize(
                                        width: steadyOffset.width + value.translation.width,
                                        height: steadyOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in steadyOffset = offset }
                        )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3)) { toggleZoom() }
                }
                .onTapGesture {
                    if steadyScale <= 1 { dismiss() }
                }
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                Spacer()
            }
            .padding(20)
        }
        .statusBarHidden()
        .task { await loadCover() }
    }

    @ViewBuilder private var cover: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            CoverArtView(seed: seed, cornerRadius: 0)
                .aspectRatio(1, contentMode: .fit)
                .padding(28)
        }
    }

    /// Decoded off the main thread at a generous size — enough detail to zoom
    /// into, without the full-resolution decode stalling the presentation.
    private func loadCover() async {
        guard let coverPath, let libraryFolder else { return }
        let url = libraryFolder.appendingPathComponent(coverPath)
        image = await CoverImageLoader.shared.image(at: url, path: coverPath, maxPixel: CoverSize.viewer)
    }

    private func toggleZoom() {
        if scale > 1 {
            resetPosition()
        } else {
            scale = 2.5
            steadyScale = 2.5
        }
    }

    private func resetPosition() {
        scale = 1
        steadyScale = 1
        offset = .zero
        steadyOffset = .zero
    }
}
