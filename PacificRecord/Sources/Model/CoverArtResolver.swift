import Foundation
import VinylCore

/// User-selectable cover-art sources, in the default fallback order.
enum CoverSource: String, CaseIterable, Identifiable {
    case appleMusic
    case coverArtArchive
    case discogs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .coverArtArchive: return "Cover Art Archive"
        case .discogs: return "Discogs"
        }
    }

    static let storageKey = "coverSource"

    static var preferred: CoverSource {
        CoverSource(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .appleMusic
    }
}

/// A cover option surfaced during a manual pick.
struct CoverCandidate: Identifiable, Hashable {
    let source: CoverSource
    let url: URL
    var id: String { url.absoluteString }
}

/// Chooses the best cover URL, trying the user's preferred source first and
/// falling back through the others until one yields an image. Apple Music is
/// the official high-res artwork; Cover Art Archive and Discogs cover more
/// pressings.
enum CoverArtResolver {
    /// UserDefaults key: when true, the import flow lets you pick the cover.
    static let pickCoverOnImportKey = "pickCoverOnImport"

    static func bestURL(
        artist: String,
        title: String,
        barcode: String? = nil,
        musicbrainzMBID: String? = nil,
        discogsFallback: URL? = nil
    ) async -> URL? {
        for source in orderedSources() {
            switch source {
            case .appleMusic:
                if let url = (try? await AppleArtworkClient().artworkURL(artist: artist, title: title)) ?? nil {
                    return url
                }
            case .coverArtArchive:
                let mbid: String?
                if let known = musicbrainzMBID {
                    mbid = known
                } else {
                    mbid = await resolveMBID(barcode: barcode, artist: artist, title: title)
                }
                if let mbid, let url = (try? await CoverArtArchiveClient().frontCoverURL(mbid: mbid)) ?? nil {
                    return url
                }
            case .discogs:
                if let discogsFallback { return discogsFallback }
            }
        }
        return discogsFallback
    }

    /// Every source that has an image for this record, ordered with the
    /// preferred source first — for the manual cover picker.
    static func candidates(
        artist: String,
        title: String,
        barcode: String? = nil,
        musicbrainzMBID: String? = nil,
        discogsFallback: URL? = nil
    ) async -> [CoverCandidate] {
        var found: [CoverCandidate] = []

        if let apple = (try? await AppleArtworkClient().artworkURL(artist: artist, title: title)) ?? nil {
            found.append(CoverCandidate(source: .appleMusic, url: apple))
        }

        let mbid: String?
        if let known = musicbrainzMBID {
            mbid = known
        } else {
            mbid = await resolveMBID(barcode: barcode, artist: artist, title: title)
        }
        if let mbid, let caa = (try? await CoverArtArchiveClient().frontCoverURL(mbid: mbid)) ?? nil {
            found.append(CoverCandidate(source: .coverArtArchive, url: caa))
        }

        if let discogsFallback {
            found.append(CoverCandidate(source: .discogs, url: discogsFallback))
        }

        let order = orderedSources()
        return found.sorted {
            (order.firstIndex(of: $0.source) ?? Int.max) < (order.firstIndex(of: $1.source) ?? Int.max)
        }
    }

    /// Preferred source first, then the remaining sources in default order.
    private static func orderedSources() -> [CoverSource] {
        let preferred = CoverSource.preferred
        return [preferred] + CoverSource.allCases.filter { $0 != preferred }
    }

    /// Finds a MusicBrainz release MBID (for the Cover Art Archive) via barcode,
    /// then artist + title.
    private static func resolveMBID(barcode: String?, artist: String, title: String) async -> String? {
        let client = MusicBrainzClient()
        if let barcode, !barcode.isEmpty,
           let results = try? await client.searchByBarcode(barcode),
           let mbid = results.first?.musicbrainzMBID {
            return mbid
        }
        let query = "\(artist) \(title)".trimmingCharacters(in: .whitespaces)
        if !query.isEmpty,
           let results = try? await client.searchByText(query),
           let mbid = results.first?.musicbrainzMBID {
            return mbid
        }
        return nil
    }
}
