import Foundation

/// Record condition on the standard Goldmine grading scale, used for both the
/// media (the disc itself) and the sleeve.
public enum Condition: String, Codable, CaseIterable, Sendable, Equatable {
    case mint = "M"
    case nearMint = "NM"
    case veryGoodPlus = "VG+"
    case veryGood = "VG"
    case goodPlus = "G+"
    case good = "G"
    case fair = "F"
    case poor = "P"

    /// Human-readable label for pickers, e.g. "Very Good Plus (VG+)".
    public var displayName: String {
        switch self {
        case .mint: return "Mint (M)"
        case .nearMint: return "Near Mint (NM)"
        case .veryGoodPlus: return "Very Good Plus (VG+)"
        case .veryGood: return "Very Good (VG)"
        case .goodPlus: return "Good Plus (G+)"
        case .good: return "Good (G)"
        case .fair: return "Fair (F)"
        case .poor: return "Poor (P)"
        }
    }

    /// Higher means better condition. Sort best → worst with
    /// `sorted { $0.qualityRank > $1.qualityRank }`.
    public var qualityRank: Int {
        switch self {
        case .mint: return 8
        case .nearMint: return 7
        case .veryGoodPlus: return 6
        case .veryGood: return 5
        case .goodPlus: return 4
        case .good: return 3
        case .fair: return 2
        case .poor: return 1
        }
    }

    /// Maps a Discogs price-suggestion key (e.g. "Near Mint (NM or M-)") to a
    /// grade. Order matters — "Near Mint" contains "Mint", "Very Good Plus"
    /// contains "Very Good", etc.
    public init?(discogsPriceKey key: String) {
        let text = key.lowercased()
        if text.contains("near mint") { self = .nearMint }
        else if text.contains("mint") { self = .mint }
        else if text.contains("very good plus") || text.contains("(vg+") { self = .veryGoodPlus }
        else if text.contains("very good") { self = .veryGood }
        else if text.contains("good plus") || text.contains("(g+") { self = .goodPlus }
        else if text.contains("good") { self = .good }
        else if text.contains("fair") { self = .fair }
        else if text.contains("poor") { self = .poor }
        else { return nil }
    }
}
