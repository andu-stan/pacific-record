import Foundation
import Observation
import VinylCore

/// Drives the add-a-record flow: runs barcode/text lookups against the metadata
/// providers, downloads cover art, and produces a prefilled draft for the form.
@MainActor
@Observable
final class AddFlowModel {
    enum Step: Hashable {
        case matches
        case coverPicker
        case form
    }

    enum Phase: Equatable {
        case idle
        case searching
        case empty
        case failed(String)
    }

    var path: [Step] = []
    var phase: Phase = .idle
    var matches: [MetadataMatch] = []
    var draft: RecordDetail?
    var lastBarcode: String?
    var coverCandidates: [CoverCandidate] = []
    private var pendingMatch: MetadataMatch?
    private var pendingRecordID: String?

    /// Seed for the picker's gradient placeholders (the chosen release title).
    var pickerSeed: String { pendingMatch?.title ?? "" }

    let provider: any MetadataProvider
    private let library: LibraryModel
    private let onFinishFlow: () -> Void
    private var lastSearch: (@Sendable () async throws -> [MetadataMatch])?
    private var lastPush = true

    init(library: LibraryModel, onFinish: @escaping () -> Void) {
        self.library = library
        self.onFinishFlow = onFinish
        self.provider = AddFlowModel.makeProvider()
    }

    /// Discogs (if a token is configured) with MusicBrainz as fallback; just
    /// MusicBrainz otherwise.
    private static func makeProvider() -> any MetadataProvider {
        let token = UserDefaults.standard.string(forKey: "discogsToken") ?? ""
        let musicBrainz = MusicBrainzClient()
        guard !token.isEmpty else { return musicBrainz }
        return CompositeMetadataProvider(providers: [DiscogsClient(token: token), musicBrainz])
    }

    // MARK: Searching

    func handleBarcode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only accept a scan while still on the scanner (nothing pushed yet).
        guard !trimmed.isEmpty, phase != .searching, path.isEmpty else { return }
        lastBarcode = trimmed
        Haptics.impact()
        let provider = provider
        // Barcode results push to the Match screen ("pick the pressing").
        run(push: true) { try await provider.searchByBarcode(trimmed) }
    }

    func runTextSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, phase != .searching else { return }
        lastBarcode = nil
        let provider = provider
        // Text results appear inline on the search screen.
        run(push: false) { try await provider.searchByText(trimmed) }
    }

    func retry() {
        if let search = lastSearch { run(push: lastPush, search) }
    }

    func dismissAlert() {
        phase = .idle
    }

    private func run(push: Bool, _ operation: @escaping @Sendable () async throws -> [MetadataMatch]) {
        lastSearch = operation
        lastPush = push
        phase = .searching
        Task {
            do {
                let results = try await operation()
                if results.isEmpty {
                    phase = .empty
                    Haptics.warning()
                } else {
                    matches = results
                    phase = .idle
                    if push && !path.contains(.matches) { path.append(.matches) }
                }
            } catch {
                phase = .failed(Self.message(for: error))
                Haptics.warning()
            }
        }
    }

    // MARK: Choosing / manual

    func choose(_ match: MetadataMatch) {
        guard phase != .searching else { return }
        phase = .searching
        Task {
            let recordID = UUID().uuidString
            var enriched = match
            if let full = try? await provider.enrich(match) { enriched = full }

            if UserDefaults.standard.bool(forKey: CoverArtResolver.pickCoverOnImportKey) {
                let candidates = await CoverArtResolver.candidates(
                    artist: enriched.artistDisplay,
                    title: enriched.title,
                    barcode: enriched.barcode,
                    musicbrainzMBID: enriched.musicbrainzMBID,
                    discogsReleaseID: enriched.discogsReleaseID,
                    discogsFallback: enriched.coverImageURL)
                if candidates.isEmpty {
                    draft = RecordDetail.draft(from: enriched, id: recordID)
                    phase = .idle
                    path.append(.form)
                } else {
                    pendingMatch = enriched
                    pendingRecordID = recordID
                    coverCandidates = candidates
                    phase = .idle
                    path.append(.coverPicker)
                }
            } else {
                // Prefer the user's cover source (Apple by default), then the others.
                let coverURL = await CoverArtResolver.bestURL(
                    artist: enriched.artistDisplay,
                    title: enriched.title,
                    barcode: enriched.barcode,
                    musicbrainzMBID: enriched.musicbrainzMBID,
                    discogsFallback: enriched.coverImageURL)
                let cover = await downloadCover(url: coverURL, recordID: recordID)
                draft = RecordDetail.draft(from: enriched, id: recordID, coverPath: cover.path, thumbPath: cover.thumb)
                phase = .idle
                path.append(.form)
            }
        }
    }

    /// Called from the cover picker; nil means "no cover".
    func selectCover(_ candidate: CoverCandidate?) {
        guard let match = pendingMatch, let recordID = pendingRecordID, phase != .searching else { return }
        phase = .searching
        Task {
            var cover: (path: String?, thumb: String?) = (nil, nil)
            if let candidate {
                cover = await downloadCover(url: candidate.url, recordID: recordID)
            }
            draft = RecordDetail.draft(from: match, id: recordID, coverPath: cover.path, thumbPath: cover.thumb)
            phase = .idle
            path.append(.form)
        }
    }

    func goManual() {
        draft = nil
        phase = .idle
        if path.last != .form { path.append(.form) }
    }

    func finish() {
        onFinishFlow()
    }

    var onComplete: () -> Void {
        let finish = onFinishFlow
        return { finish() }
    }

    var formDraft: RecordDetail {
        draft ?? RecordDetail(release: Release(id: UUID().uuidString, title: "", artistDisplay: ""))
    }

    // MARK: Helpers

    private func downloadCover(url: URL?, recordID: String) async -> (path: String?, thumb: String?) {
        guard let url else { return (nil, nil) }
        do {
            let result = try await CoverImageManager().downloadCover(from: url, releaseID: recordID, into: library.libraryFolder)
            return (result.coverPath, result.thumbPath)
        } catch {
            return (nil, nil)
        }
    }

    // Pure error → message mapping; nonisolated so background sync/import code
    // (off the main actor) can reuse it.
    nonisolated static func message(for error: Error) -> String {
        if let error = error as? MetadataError {
            switch error {
            case .http(429):
                return "Discogs is rate-limiting requests. Wait a few seconds and try again."
            case let .http(status) where status == 401 || status == 403:
                return "Discogs rejected the request — check your API token in Settings."
            case let .http(status):
                return "The lookup service returned an error (HTTP \(status))."
            case .invalidURL:
                return "Couldn't build the lookup request."
            case .noResults:
                return "No results were returned."
            }
        }
        return (error as NSError).localizedDescription
    }
}
