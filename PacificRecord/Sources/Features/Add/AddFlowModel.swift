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
    /// True when the last search did find releases but they were all on media
    /// the user filtered out — the "no match" alert says so instead of blaming
    /// the release.
    private(set) var lastSearchWasFilteredOut = false
    private var pendingMatch: MetadataMatch?
    private var pendingRecordID: String?

    /// Seed for the picker's gradient placeholders (the chosen release title).
    var pickerSeed: String { pendingMatch?.title ?? "" }

    /// Built once per flow, so its rate limiter throttles every call the flow
    /// makes. The flow is created fresh each time Add opens, which is also when
    /// it picks up the current token and media selection.
    let provider: any MetadataProvider

    /// The same Discogs client the provider uses (a struct, but its rate
    /// limiter is shared), for the pressing-detail reads that sit outside the
    /// `MetadataProvider` protocol. Present even without a token, since the
    /// release endpoint is a public read.
    private let discogs: DiscogsClient
    private let library: LibraryModel
    private let onFinishFlow: () -> Void
    private var lastSearch: (@Sendable () async throws -> [MetadataMatch])?
    private var lastKind: SearchKind = .text

    init(library: LibraryModel, onFinish: @escaping () -> Void) {
        self.library = library
        self.onFinishFlow = onFinish
        let built = AddFlowModel.makeProvider()
        self.provider = built.provider
        self.discogs = built.discogs
    }

    /// Discogs (if a token is configured) with MusicBrainz as fallback; just
    /// MusicBrainz otherwise. The Discogs client comes back either way so
    /// pressing details still work on a token-less install.
    private static func makeProvider() -> (provider: any MetadataProvider, discogs: DiscogsClient) {
        let token = DiscogsTokenStore.read()
        let discogs = DiscogsClient(token: token, mediums: SearchMediums.current)
        let musicBrainz = MusicBrainzClient()
        guard !token.isEmpty else { return (musicBrainz, discogs) }
        return (CompositeMetadataProvider(providers: [discogs, musicBrainz]), discogs)
    }

    // MARK: Searching

    /// Barcode and text lookups want different handling of the results, so the
    /// two paths are named rather than passed as a pile of flags.
    private enum SearchKind {
        case barcode
        case text

        /// Barcode results go to the Match screen ("pick the pressing"); text
        /// results appear inline on the search screen.
        var pushesMatchScreen: Bool { self == .barcode }

        /// You scanned something physical, so if the medium filter would empty
        /// the results, show them anyway rather than claiming no match.
        var ignoresMediumFilterWhenEmpty: Bool { self == .barcode }

        /// Every barcode result is the same record in a different pressing, so
        /// the one most people own is almost certainly the one in your hands.
        /// Text results keep Discogs' relevance order — re-ranking those would
        /// push a famous album above a closer title match.
        var ranksByPopularity: Bool { self == .barcode }
    }

    func handleBarcode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only accept a scan while still on the scanner (nothing pushed yet).
        guard !trimmed.isEmpty, phase != .searching, path.isEmpty else { return }
        lastBarcode = trimmed
        Haptics.impact()
        let provider = provider
        run(.barcode) { try await provider.searchByBarcode(trimmed) }
    }

    func runTextSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, phase != .searching else { return }
        lastBarcode = nil
        let provider = provider
        run(.text) { try await provider.searchByText(trimmed) }
    }

    func retry() {
        if let search = lastSearch { run(lastKind, search) }
    }

    func dismissAlert() {
        phase = .idle
    }

    private func run(_ kind: SearchKind, _ operation: @escaping @Sendable () async throws -> [MetadataMatch]) {
        lastSearch = operation
        lastKind = kind
        phase = .searching
        expandedDetails = []
        Task {
            do {
                let found = try await operation()
                let filter = SearchMediums.current
                var results = filter.apply(to: found)
                if results.isEmpty && kind.ignoresMediumFilterWhenEmpty { results = found }
                lastSearchWasFilteredOut = results.isEmpty && !found.isEmpty
                if results.isEmpty {
                    phase = .empty
                    Haptics.warning()
                } else {
                    matches = kind.ranksByPopularity ? Self.rankedByPopularity(results) : results
                    phase = .idle
                    if kind.pushesMatchScreen && !path.contains(.matches) { path.append(.matches) }
                }
            } catch {
                phase = .failed(Self.message(for: error))
                Haptics.warning()
            }
        }
    }

    /// Most-owned pressing first, keeping the source's order among candidates
    /// with the same (or no) count so the sort is stable.
    private static func rankedByPopularity(_ matches: [MetadataMatch]) -> [MetadataMatch] {
        matches.enumerated().sorted { lhs, rhs in
            let left = lhs.element.community?.have ?? -1
            let right = rhs.element.community?.have ?? -1
            if left != right { return left > right }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    // MARK: Pressing detail

    /// What a candidate row should show below itself. Details cost a
    /// rate-limited request each, so they're fetched only when asked for and
    /// kept for the rest of the flow.
    enum DetailState: Equatable {
        /// Not a Discogs release — nothing to expand.
        case unavailable
        case collapsed
        case loading
        case loaded(PressingDetail)
        case failed(String)
    }

    private var expandedDetails: Set<Int> = []
    private var details: [Int: PressingDetail] = [:]
    private var detailFailures: [Int: String] = [:]
    private var loadingDetails: Set<Int> = []

    func detailState(for match: MetadataMatch) -> DetailState {
        guard let id = match.discogsReleaseID else { return .unavailable }
        guard expandedDetails.contains(id) else { return .collapsed }
        if let detail = details[id] { return .loaded(detail) }
        if let message = detailFailures[id] { return .failed(message) }
        return .loading
    }

    func toggleDetails(for match: MetadataMatch) {
        guard let id = match.discogsReleaseID else { return }
        if expandedDetails.contains(id) {
            expandedDetails.remove(id)
            return
        }
        expandedDetails.insert(id)
        loadDetail(id)
    }

    /// Re-runs a fetch that failed, without collapsing the row.
    func retryDetail(for match: MetadataMatch) {
        guard let id = match.discogsReleaseID else { return }
        detailFailures[id] = nil
        loadDetail(id)
    }

    private func loadDetail(_ id: Int) {
        guard details[id] == nil, !loadingDetails.contains(id) else { return }
        loadingDetails.insert(id)
        let client = discogs
        let currency = UserDefaults.standard.string(forKey: RecordValueService.currencyKey)
        Task {
            do {
                details[id] = try await client.pressingDetail(releaseID: id, currency: currency)
            } catch {
                detailFailures[id] = Self.message(for: error)
            }
            loadingDetails.remove(id)
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
            case .responseTooLarge:
                return "The lookup service sent back far more data than expected."
            }
        }
        return (error as NSError).localizedDescription
    }
}
