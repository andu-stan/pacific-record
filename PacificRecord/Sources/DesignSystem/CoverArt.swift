import SwiftUI
import UIKit

/// A gradient "cover" used as a placeholder until real artwork is downloaded.
/// The seeded sample records reproduce the exact gradients from the design;
/// any other record gets a deterministic gradient derived from its name.
struct CoverStyle {
    enum Shape {
        case linear(start: UnitPoint, end: UnitPoint)
        case elliptical(center: UnitPoint)
    }

    let stops: [Gradient.Stop]
    let shape: Shape

    @ViewBuilder
    var view: some View {
        let gradient = Gradient(stops: stops)
        switch shape {
        case let .linear(start, end):
            LinearGradient(gradient: gradient, startPoint: start, endPoint: end)
        case let .elliptical(center):
            EllipticalGradient(gradient: gradient, center: center)
        }
    }

    static func linear(_ colors: [(UInt, Double)], _ start: UnitPoint, _ end: UnitPoint) -> CoverStyle {
        CoverStyle(stops: colors.map { .init(color: Color(hex: $0.0), location: $0.1) },
                   shape: .linear(start: start, end: end))
    }

    static func elliptical(_ colors: [(UInt, Double)], _ center: UnitPoint) -> CoverStyle {
        CoverStyle(stops: colors.map { .init(color: Color(hex: $0.0), location: $0.1) },
                   shape: .elliptical(center: center))
    }
}

enum CoverGradient {
    /// Exact gradients for the seeded sample library (keyed by album title).
    private static let known: [String: CoverStyle] = [
        "kind of blue": .linear([(0x0A2A4A, 0), (0x13416B, 0.55), (0x2166A0, 1)], .top, .bottom),
        "a love supreme": .linear([(0x0A0A0A, 0.45), (0x8A3A10, 0.80), (0xD2691E, 1)], .top, .bottom),
        "rumours": .linear([(0xEFE6D4, 0), (0xD8C39C, 0.55), (0x3A2F24, 1)], .topLeading, .bottomTrailing),
        "to pimp a butterfly": .elliptical([(0x2B2B2B, 0), (0x0A0A0A, 0.70)], .init(x: 0.5, y: 1.1)),
        "random access memories": .elliptical([(0xF4C760, 0), (0x8A5A12, 0.58), (0x0F0A04, 1)], .init(x: 0.5, y: 0.42)),
        "the velvet underground & nico": .linear([(0xF2D43A, 0), (0xE6BF1E, 0.55), (0xF5F2E8, 1)], .topLeading, .bottomTrailing),
        "ok computer": .linear([(0xE2E9EC, 0), (0xA6B6BB, 0.68), (0x54666C, 1)], .top, .bottom),
        "what's going on": .linear([(0x0A2A1E, 0), (0x1F5A3A, 0.60), (0x3A8A54, 1)], .top, .bottom),
        "remain in light": .linear([(0xC0281E, 0), (0x7A140E, 0.60), (0x1A0A08, 1)], .top, .bottom),
        "pastel blues": .linear([(0x3A2830, 0), (0x7A4A55, 0.60), (0xC39AA0, 1)], .top, .bottom),
        "selected ambient works 85–92": .elliptical([(0x1A5A6A, 0), (0x0A2028, 0.70)], .init(x: 0.5, y: 0.45)),
        "dummy": .linear([(0x151515, 0), (0x2A2A2A, 0.60), (0x454545, 1)], .top, .bottom),
    ]

    /// Deterministic fallback palettes for records not in the sample set.
    private static let fallbacks: [CoverStyle] = [
        .linear([(0x1B4B6B, 0), (0x0E2436, 1)], .topLeading, .bottomTrailing),
        .linear([(0x6B2B1B, 0), (0x2A0F0A, 1)], .topLeading, .bottomTrailing),
        .linear([(0x2A2A2E, 0), (0x0C0C0E, 1)], .top, .bottom),
        .linear([(0x2E5A3A, 0), (0x0F2417, 1)], .topLeading, .bottomTrailing),
        .elliptical([(0x5A4A1A, 0), (0x120E04, 0.72)], .center),
        .linear([(0x4A2A55, 0), (0x1A0E20, 1)], .top, .bottom),
    ]

    static func style(for seed: String) -> CoverStyle {
        let key = seed.lowercased()
        if let style = known[key] { return style }
        var hash: UInt64 = 5381
        for byte in seed.utf8 { hash = (hash &* 33) ^ UInt64(byte) }
        return fallbacks[Int(hash % UInt64(fallbacks.count))]
    }
}

/// The subtle top-left sheen used on every cover.
private var coverSheen: some View {
    LinearGradient(
        colors: [.white.opacity(0.16), .clear],
        startPoint: .topLeading,
        endPoint: UnitPoint(x: 0.42, y: 0.42)
    )
}

/// A record's cover: the downloaded image if present on disk, otherwise a
/// deterministic gradient placeholder.
struct CoverArtView: View {
    let seed: String
    var coverPath: String? = nil
    var cornerRadius: CGFloat = Metrics.tileRadius

    @Environment(\.libraryFolderURL) private var libraryFolder

    var body: some View {
        Group {
            if let image = localImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                CoverGradient.style(for: seed).view.overlay(coverSheen)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private var localImage: UIImage? {
        guard let coverPath, let libraryFolder else { return nil }
        return UIImage(contentsOfFile: libraryFolder.appendingPathComponent(coverPath).path)
    }
}

/// A cover loaded from a remote URL (search/match results), with a gradient
/// placeholder while loading or on failure.
struct RemoteCoverView: View {
    let url: URL?
    let seed: String
    var cornerRadius: CGFloat = 6

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        CoverGradient.style(for: seed).view.overlay(coverSheen)
                    }
                }
            } else {
                CoverGradient.style(for: seed).view.overlay(coverSheen)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}
