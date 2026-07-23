import Foundation
import VinylCore

/// Fetches an estimated market value for a record from Discogs: a price
/// suggestion for the record's media condition when a token is configured,
/// otherwise the lowest current listing.
enum RecordValueService {
    struct Estimate: Sendable {
        var amount: Double
        var currency: String
        var basis: String   // a Goldmine grade ("NM") or "Lowest listing"
    }

    static func fetch(for release: Release) async -> Estimate? {
        guard let releaseID = release.discogsReleaseID else { return nil }
        let token = UserDefaults.standard.string(forKey: "discogsToken") ?? ""
        let client = DiscogsClient(token: token)

        if !token.isEmpty, let suggestions = try? await client.priceSuggestions(releaseID: releaseID), !suggestions.isEmpty {
            let condition = release.mediaCondition ?? .nearMint
            let money = suggestions[condition]
                ?? suggestions[.nearMint]
                ?? suggestions.max(by: { $0.value.amount < $1.value.amount })?.value
            if let money {
                return Estimate(amount: money.amount, currency: money.currency, basis: condition.rawValue)
            }
        }

        if let lowest = try? await client.lowestListingPrice(releaseID: releaseID) {
            return Estimate(amount: lowest.amount, currency: lowest.currency, basis: "Lowest listing")
        }
        return nil
    }
}
