import SwiftUI
import VinylCore

/// The two-column cover grid shared by the import flow (`CoverPickerView`) and
/// the record form's "Replace cover art" sheet, so both look and behave the same.
struct CoverChooserGrid: View {
    let candidates: [CoverCandidate]
    let seed: String
    var onPick: (CoverCandidate) -> Void

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(candidates) { candidate in
                Button { onPick(candidate) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        RemoteCoverView(url: candidate.url, seed: seed, cornerRadius: 8)
                            .aspectRatio(1, contentMode: .fit)
                            .shadow(color: .black.opacity(0.5), radius: 7, y: 4)
                        Text(candidate.source.displayName)
                            .font(.prSmall).foregroundStyle(Palette.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Presents the cover grid for a record that already exists as a form draft
/// (a manual entry, or an edit) and downloads the chosen image into the library
/// folder, handing the resulting relative paths back to the form.
struct CoverChooserSheet: View {
    let candidates: [CoverCandidate]
    let seed: String
    /// A unique, timestamped file id so a re-pick writes a fresh cover file.
    let fileID: String
    let folder: URL
    /// Called with the new (coverPath, thumbPath) once the download succeeds.
    var onPicked: (String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var downloading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pick the cover to use for this record.")
                        .font(.prBody).foregroundStyle(Palette.secondary)
                    CoverChooserGrid(candidates: candidates, seed: seed) { download($0) }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Palette.background)
            .navigationTitle("Choose cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.disabled(downloading)
                }
            }
            .overlay {
                if downloading {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        ProgressView().controlSize(.large).tint(.white)
                    }
                }
            }
            .interactiveDismissDisabled(downloading)
        }
        .tint(Palette.tint)
    }

    private func download(_ candidate: CoverCandidate) {
        guard !downloading else { return }
        downloading = true
        Task {
            if let result = try? await CoverImageManager().downloadCover(from: candidate.url, releaseID: fileID, into: folder) {
                onPicked(result.coverPath, result.thumbPath)
                Haptics.success()
                dismiss()
            } else {
                Haptics.warning()
                downloading = false
            }
        }
    }
}
