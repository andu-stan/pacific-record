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
}
