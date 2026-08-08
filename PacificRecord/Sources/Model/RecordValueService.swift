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

    /// UserDefaults key for the preferred marketplace currency.
    static let currencyKey = "discogsCurrency"

    /// UserDefaults key: show each record's value in the Library list. Off by
    /// default — most browsing doesn't want prices on screen.
    static let showValueInListKey = "showValueInList"

    /// The currency to price in. Discogs honours this for the lowest-listing
    /// lookup; condition suggestions come back in the token account's currency.
    static var preferredCurrency: String {
        let stored = UserDefaults.standard.string(forKey: currencyKey) ?? ""
        return DiscogsCurrency.isSupported(stored) ? stored : "USD"
    }

    /// A client for a run of lookups. Reuse one across a bulk refresh: the rate
    /// limiter lives on the instance, so a fresh client per record would issue
    /// unthrottled requests and get rate-limited by Discogs.
    static func makeClient() -> DiscogsClient {
        DiscogsClient(token: DiscogsTokenStore.read())
    }

    static func fetch(for release: Release) async -> Estimate? {
        await fetch(for: release, using: makeClient())
    }

    static func fetch(for release: Release, using client: DiscogsClient) async -> Estimate? {
        guard let releaseID = release.discogsReleaseID else { return nil }
        let token = DiscogsTokenStore.read()
        let currency = preferredCurrency

        if !token.isEmpty, let suggestions = try? await client.priceSuggestions(releaseID: releaseID), !suggestions.isEmpty {
            let condition = release.mediaCondition ?? .nearMint
            let money = suggestions[condition]
                ?? suggestions[.nearMint]
                ?? suggestions.max(by: { $0.value.amount < $1.value.amount })?.value
            if let money {
                return Estimate(amount: money.amount, currency: money.currency, basis: condition.rawValue)
            }
        }

        if let lowest = try? await client.lowestListingPrice(releaseID: releaseID, currency: currency) {
            return Estimate(amount: lowest.amount, currency: lowest.currency, basis: "Lowest listing")
        }
        return nil
    }

    /// True when a record can be valued and its stored value is missing or no
    /// longer reflects its media grade — the rule behind both the automatic
    /// lookup (once both conditions are graded) and the bulk refresh.
    static func needsValue(_ release: Release) -> Bool {
        guard release.discogsReleaseID != nil else { return false }
        guard release.estimatedValue != nil else { return true }
        // The value is condition-specific, so a re-grade invalidates it.
        if let media = release.mediaCondition, release.valueBasis != media.rawValue { return true }
        return false
    }
}
