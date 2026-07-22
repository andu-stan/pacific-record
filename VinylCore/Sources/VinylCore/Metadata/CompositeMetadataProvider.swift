import Foundation

/// Chains providers so lookups try Discogs first and fall back to MusicBrainz
/// only when Discogs returns nothing. `enrich(_:)` routes back to whichever
/// provider produced the match.
public struct CompositeMetadataProvider: MetadataProvider {
    /// Nominal; the composite itself isn't tied to one source. `enrich(_:)`
    /// dispatches on each match's own `source`.
    public let source: MetadataSource = .discogs

    private let providers: [MetadataProvider]

    public init(providers: [MetadataProvider]) {
        self.providers = providers
    }

    public init(discogs: DiscogsClient, musicBrainz: MusicBrainzClient) {
        self.providers = [discogs, musicBrainz]
    }

    public func searchByBarcode(_ barcode: String) async throws -> [MetadataMatch] {
        try await firstNonEmpty { try await $0.searchByBarcode(barcode) }
    }

    public func searchByText(_ query: String) async throws -> [MetadataMatch] {
        try await firstNonEmpty { try await $0.searchByText(query) }
    }

    public func enrich(_ match: MetadataMatch) async throws -> MetadataMatch {
        guard let provider = providers.first(where: { $0.source == match.source }) else { return match }
        return try await provider.enrich(match)
    }

    /// Returns the first provider's non-empty results. If every provider errors,
    /// rethrows the last error; if all simply return nothing, returns empty.
    private func firstNonEmpty(
        _ operation: (MetadataProvider) async throws -> [MetadataMatch]
    ) async throws -> [MetadataMatch] {
        var lastError: Error?
        for provider in providers {
            do {
                let results = try await operation(provider)
                if !results.isEmpty { return results }
            } catch {
                lastError = error
            }
        }
        if let lastError = lastError { throw lastError }
        return []
    }
}
