import Foundation
import VinylCore

/// The result of pushing a record to the user's Discogs collection.
enum DiscogsSyncOutcome: Equatable {
    case added
    case alreadyInCollection
    case notLinked          // the record has no Discogs release id (e.g. manual entry)
    case failed(String)
}

/// Sync-back to Discogs: adds records the user creates in the app to their
/// Discogs collection. Opt-in and de-duplicated so it never creates duplicate
/// instances or touches the account without the user asking.
enum DiscogsCollectionSync {
    /// UserDefaults key for the auto-sync toggle. Off by default — this writes
    /// to the user's live Discogs account.
    static let autoSyncKey = "syncAdditionsToDiscogs"

    static var autoSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: autoSyncKey)
    }

    private static var token: String {
        UserDefaults.standard.string(forKey: "discogsToken") ?? ""
    }

    /// Pushes one record to the user's Discogs collection. Best-effort: resolves
    /// the username from the token, skips releases already in the collection,
    /// then adds and (if rated) sets the star rating.
    static func push(_ release: Release) async -> DiscogsSyncOutcome {
        guard let releaseID = release.discogsReleaseID else { return .notLinked }
        let token = token
        guard !token.isEmpty else { return .failed("Add a Discogs token in Settings first.") }

        let client = DiscogsClient(token: token)
        do {
            let username = try await client.identity()
            if try await client.collectionContains(username: username, releaseID: releaseID) {
                return .alreadyInCollection
            }
            let instanceID = try await client.addToCollection(username: username, releaseID: releaseID)
            if release.rating > 0 {
                try? await client.setCollectionRating(
                    username: username, releaseID: releaseID, instanceID: instanceID, rating: release.rating)
            }
            return .added
        } catch {
            return .failed(AddFlowModel.message(for: error))
        }
    }
}
