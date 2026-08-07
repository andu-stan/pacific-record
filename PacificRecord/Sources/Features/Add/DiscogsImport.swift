import Foundation
import Observation
import SwiftUI
import VinylCore

// MARK: - Importer

/// Streams the user's Discogs collection into the library: resolves the
/// username from the token, pages through the collection (throttled by the
/// client's rate limiter), downloads each cover, and saves — skipping releases
/// already present. Progress is observable so the UI can show it live.
@MainActor
@Observable
final class DiscogsCollectionImporter {
    enum Phase: Equatable {
        case idle
        case connecting
        case working
        case done
        case cancelled
        case failed(String)
    }

    var phase: Phase = .idle
    var username: String?
    var total = 0
    var imported = 0
    var skipped = 0
    var failedCovers = 0

    private let client: DiscogsClient
    private let store: LibraryStore
    private let libraryFolder: URL
    private let onChange: () -> Void
    private var task: Task<Void, Never>?

    init(token: String, store: LibraryStore, libraryFolder: URL, onChange: @escaping () -> Void) {
        self.client = DiscogsClient(token: token)
        self.store = store
        self.libraryFolder = libraryFolder
        self.onChange = onChange
    }

    var isRunning: Bool { phase == .connecting || phase == .working }

    /// 0 while the first page is still loading (total unknown), then advances.
    var progressFraction: Double {
        total > 0 ? min(1, Double(imported + skipped) / Double(total)) : 0
    }

    func start() {
        guard !isRunning else { return }
        total = 0; imported = 0; skipped = 0; failedCovers = 0; username = nil
        phase = .connecting
        task = Task { await run() }
    }

    func cancel() { task?.cancel() }

    private func run() async {
        do {
            let user = try await client.identity()
            username = user
            // Best-effort: only used to map media/sleeve grades if the user set
            // up those custom fields in Discogs.
            let fields = try? await client.collectionFieldIDs(username: user)
            var existing = (try? store.discogsReleaseIDs()) ?? []

            phase = .working
            var page = 1
            var totalPages = 1
            repeat {
                if Task.isCancelled { finish(.cancelled); return }
                let result = try await client.collectionPage(
                    username: user, page: page, perPage: 100,
                    mediaFieldID: fields?.media, sleeveFieldID: fields?.sleeve)
                totalPages = max(1, result.totalPages)
                if page == 1 { total = result.totalItems }

                var alreadyPresent: [Int] = []
                for entry in result.items {
                    if Task.isCancelled { finish(.cancelled); return }
                    if let rid = entry.match.discogsReleaseID, existing.contains(rid) {
                        alreadyPresent.append(rid)
                        skipped += 1
                        continue
                    }
                    await importEntry(entry)
                    if let rid = entry.match.discogsReleaseID { existing.insert(rid) }
                }
                // Backfill the synced marker for the whole page in one
                // transaction — a re-import skips everything, and doing this per
                // record meant hundreds of separate writes. Copied to a `let`
                // so the sendable closure captures a value, not the loop's var.
                let pageAlreadyPresent = alreadyPresent
                await write { try $0.markDiscogsSynced(discogsReleaseIDs: pageAlreadyPresent) }
                onChange() // let the library grid fill in as we go
                page += 1
            } while page <= totalPages

            finish(.done)
        } catch is CancellationError {
            finish(.cancelled)
        } catch {
            finish(.failed(AddFlowModel.message(for: error)))
        }
    }

    private func importEntry(_ entry: CollectionEntry) async {
        let id = UUID().uuidString
        var coverPath: String?
        var thumbPath: String?
        if let url = entry.match.coverImageURL {
            if let result = try? await CoverImageManager().downloadCover(from: url, releaseID: id, into: libraryFolder) {
                coverPath = result.coverPath
                thumbPath = result.thumbPath
            } else {
                failedCovers += 1
            }
        }
        var detail = RecordDetail.draft(
            from: entry.match, id: id,
            coverPath: coverPath, thumbPath: thumbPath,
            mediaCondition: entry.mediaCondition, sleeveCondition: entry.sleeveCondition,
            rating: entry.rating)
        detail.release.discogsSyncedAt = Date() // imported records are already in the Discogs collection
        let saved = detail
        await write { try $0.save(saved) }
        imported += 1
    }

    /// Runs a blocking database write off the main thread. Importing a large
    /// collection is hundreds of writes; on the main actor they stuttered the UI.
    private func write(_ work: @escaping @Sendable (LibraryStore) throws -> Void) async {
        let store = self.store
        await Task.detached(priority: .utility) { try? work(store) }.value
    }

    private func finish(_ phase: Phase) {
        self.phase = phase
        onChange()
        if phase == .done { Haptics.success() }
    }
}

// MARK: - View

struct DiscogsImportView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("discogsToken") private var token = ""
    @State private var importer: DiscogsCollectionImporter?

    private var running: Bool { importer?.isRunning ?? false }

    var body: some View {
        NavigationStack {
            Group {
                if token.isEmpty {
                    noToken
                } else if let importer {
                    progress(importer)
                } else {
                    intro
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
            .navigationTitle("Import collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if running {
                        Button("Stop") { importer?.cancel() }
                    } else {
                        Button("Done") { dismiss() }.fontWeight(.semibold)
                    }
                }
            }
        }
        .tint(Palette.tint)
        .interactiveDismissDisabled(running)
    }

    // MARK: States

    private var intro: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 46))
                .foregroundStyle(Palette.accent)
            Text("Import your Discogs collection")
                .font(.prTitle2).foregroundStyle(Palette.label)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                bullet("Pulls every release from your collection — title, artist, label, year, format, genre, and your Discogs rating.")
                bullet("Downloads each cover (this is the slow part for a big collection).")
                bullet("Skips releases already in your library, so you can run it again to sync new additions.")
            }
            .padding(.top, 4)
            Spacer()
            PrimaryButton(title: "Start import") {
                let created = model.makeDiscogsImporter(token: token)
                importer = created
                created.start()
            }
            Text("Keep the app open while it runs.")
                .font(.prSmall).foregroundStyle(Palette.tertiary)
                .padding(.bottom, 8)
        }
    }

    private func progress(_ importer: DiscogsCollectionImporter) -> some View {
        VStack(spacing: 20) {
            Spacer()
            switch importer.phase {
            case .done:
                icon("checkmark.circle.fill", Palette.positive)
                Text("Import complete").font(.prTitle2).foregroundStyle(Palette.label)
                Text(summary(importer)).font(.prBody).foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
            case .failed(let message):
                icon("exclamationmark.triangle.fill", Palette.danger)
                Text("Import failed").font(.prTitle2).foregroundStyle(Palette.label)
                Text(message).font(.prBody).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            case .cancelled:
                icon("stop.circle.fill", Palette.secondary)
                Text("Import stopped").font(.prTitle2).foregroundStyle(Palette.label)
                Text(summary(importer)).font(.prBody).foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
            default:
                if importer.total > 0 {
                    ProgressView(value: importer.progressFraction)
                        .tint(Palette.accent)
                        .padding(.horizontal, 8)
                } else {
                    ProgressView().controlSize(.large).tint(Palette.accent)
                }
                Text(importer.phase == .connecting ? "Connecting to Discogs…" : "Importing your collection…")
                    .font(.prBodyEmphasis).foregroundStyle(Palette.label)
                Text(liveCounts(importer)).font(.prBody).foregroundStyle(Palette.secondary)
                if let user = importer.username {
                    Text("@\(user)").font(.prSmall).foregroundStyle(Palette.tertiary)
                }
            }
            Spacer()
            if !importer.isRunning {
                PrimaryButton(title: "Done") { dismiss() }.padding(.bottom, 8)
            }
        }
    }

    private var noToken: some View {
        VStack(spacing: 14) {
            Spacer()
            icon("key.horizontal", Palette.tertiary)
            Text("Connect Discogs first").font(.prTitle2).foregroundStyle(Palette.label)
            Text("Add your Discogs API token in the Metadata section of Settings, then come back to import your collection.")
                .font(.prBody).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            Spacer()
            PrimaryButton(title: "Done") { dismiss() }.padding(.bottom, 8)
        }
    }

    // MARK: Bits

    private func icon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name).font(.system(size: 46)).foregroundStyle(color)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Palette.accent).padding(.top, 7)
            Text(text).font(.prBody).foregroundStyle(Palette.secondary)
        }
    }

    private func liveCounts(_ importer: DiscogsCollectionImporter) -> String {
        let done = importer.imported + importer.skipped
        if importer.total > 0 { return "\(done) of \(importer.total) · \(importer.imported) added" }
        return "\(importer.imported) added"
    }

    private func summary(_ importer: DiscogsCollectionImporter) -> String {
        var parts = ["Added \(importer.imported) record\(importer.imported == 1 ? "" : "s")"]
        if importer.skipped > 0 { parts.append("skipped \(importer.skipped) already in your library") }
        if importer.failedCovers > 0 { parts.append("\(importer.failedCovers) cover\(importer.failedCovers == 1 ? "" : "s") couldn’t be fetched") }
        return parts.joined(separator: " · ") + "."
    }
}
