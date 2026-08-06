import Foundation
import Observation
import VinylCore

/// Re-fetches Discogs values for the whole library in the background.
///
/// Owned by `LibraryModel` so a run survives the Settings sheet being
/// dismissed; the UI just observes `progress` and can stop it. Discogs is rate
/// limited to roughly one request a second, so this is deliberately slow and
/// paced by a single shared client.
@MainActor
@Observable
final class ValueRefreshCoordinator {
    enum Phase: Equatable {
        case idle
        case running
        case finished(updated: Int, failed: Int)
        case cancelled(updated: Int)
    }

    private(set) var phase: Phase = .idle
    private(set) var total = 0
    private(set) var completed = 0

    private let store: LibraryStore
    /// Set by the owner after init (it needs `self`); called as records update.
    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private var task: Task<Void, Never>?

    init(store: LibraryStore) {
        self.store = store
    }

    var isRunning: Bool { phase == .running }

    var progress: Double {
        total > 0 ? min(1, Double(completed) / Double(total)) : 0
    }

    /// Records this run would touch: everything linked to a Discogs release.
    static func candidates(in records: [Release]) -> [Release] {
        records.filter { $0.discogsReleaseID != nil }
    }

    func start(records: [Release]) {
        guard !isRunning else { return }
        let targets = Self.candidates(in: records)
        guard !targets.isEmpty else {
            phase = .finished(updated: 0, failed: 0)
            return
        }
        total = targets.count
        completed = 0
        phase = .running
        task = Task { await run(targets) }
    }

    func cancel() {
        task?.cancel()
    }

    private func run(_ targets: [Release]) async {
        // One client for the whole run so its rate limiter paces the requests.
        let client = RecordValueService.makeClient()
        var updated = 0
        var failed = 0

        for release in targets {
            if Task.isCancelled {
                phase = .cancelled(updated: updated)
                onChange()
                return
            }
            if let estimate = await RecordValueService.fetch(for: release, using: client) {
                await applyValue(estimate, to: release.id)
                updated += 1
            } else {
                failed += 1
            }
            completed += 1
            // Let the library reflect progress without hammering the UI.
            if completed % 10 == 0 { onChange() }
        }

        phase = .finished(updated: updated, failed: failed)
        onChange()
        if updated > 0 { Haptics.success() }
    }

    /// Writes just the value fields, off the main thread, re-reading the record
    /// so nothing else is clobbered.
    private func applyValue(_ estimate: RecordValueService.Estimate, to id: String) async {
        let store = self.store
        await Task.detached(priority: .utility) {
            guard var current = try? store.detail(id: id)?.release else { return }
            current.estimatedValue = estimate.amount
            current.valueCurrency = estimate.currency
            current.valueBasis = estimate.basis
            current.valueUpdatedAt = Date()
            try? store.update(current)
        }.value
    }
}
