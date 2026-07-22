import SwiftUI
import VinylCore

// MARK: - Routing

enum AddChoice: Int, Identifiable {
    case scan, search, manual
    var id: Int { rawValue }
}

/// Navigation targets shared within an add flow's NavigationStack.
enum AddRoute: Hashable {
    case match
    case candidate(PressingCandidate)
    case manual
}

/// A candidate pressing shown on the match / search screens.
struct PressingCandidate: Hashable, Identifiable {
    var id = UUID()
    var title: String
    var artist: String
    var label: String
    var catalogNumber: String
    var year: Int
    var country: String
    var format: String

    func recordDetail() -> RecordDetail {
        let recordID = UUID().uuidString
        let release = Release(
            id: recordID,
            title: title,
            artistDisplay: artist,
            year: year,
            country: country,
            format: format.components(separatedBy: ",").first,
            speed: "33⅓"
        )
        return RecordDetail(
            release: release,
            artists: [Artist(id: UUID().uuidString, name: artist)],
            labels: [LabelCredit(name: label, catalogNumber: catalogNumber)],
            tracks: []
        )
    }

    /// The candidate pressings from the design (A Love Supreme).
    static let sample: [PressingCandidate] = [
        .init(title: "A Love Supreme", artist: "John Coltrane", label: "Impulse!", catalogNumber: "A-77", year: 1965, country: "US", format: "LP, Mono"),
        .init(title: "A Love Supreme", artist: "John Coltrane", label: "Impulse!", catalogNumber: "AS-77", year: 1965, country: "US", format: "LP, Stereo"),
        .init(title: "A Love Supreme", artist: "John Coltrane", label: "Impulse! / Analogue Prod.", catalogNumber: "AAPJ 077", year: 2010, country: "US", format: "2×LP, 45 RPM, 180g"),
        .init(title: "A Love Supreme", artist: "John Coltrane", label: "HMV Pop", catalogNumber: "CLP 1869", year: 1965, country: "UK", format: "LP, Mono"),
        .init(title: "A Love Supreme", artist: "John Coltrane", label: "Impulse! / Verve", catalogNumber: "602547976598", year: 2016, country: "Europe", format: "LP, 180g"),
    ]
}

// MARK: - Chooser sheet

struct AddEntrySheet: View {
    var onSelect: (AddChoice) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Palette.quaternary)
                .frame(width: 38, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 0) {
                Text("Add a record")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(Palette.label)
                Text("Choose how you'd like to add it.")
                    .font(.prBody)
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 4)
                    .padding(.bottom, 22)

                VStack(spacing: 12) {
                    option(icon: "barcode", iconColor: Palette.accent, title: "Scan barcode",
                           subtitle: "Auto-fill details & cover art") { onSelect(.scan) }
                    option(icon: "magnifyingglass", iconColor: Palette.iCloudBlue, title: "Search by title or artist",
                           subtitle: "Look up on Discogs") { onSelect(.search) }
                    option(icon: "square.and.pencil", iconColor: Color(hex: 0x48484A), title: "Enter manually",
                           subtitle: "Fill in every field yourself") { onSelect(.manual) }
                }

                Button { dismiss() } label: {
                    Text("Cancel")
                        .font(.prHeadline)
                        .foregroundStyle(Palette.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.grouped)
        .presentationCornerRadius(26)
    }

    private func option(icon: String, iconColor: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 15) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(iconColor)
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.prHeadline).foregroundStyle(Palette.label)
                    Text(subtitle).font(.prFootnote).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.quaternary)
            }
            .padding(16)
            .background(Palette.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scanner

struct ScannerView: View {
    var onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScannerSurface(onClose: { dismiss() })
            .navigationBarHidden(true)
            .navigationDestination(for: AddRoute.self) { route in
                switch route {
                case .match:
                    MatchView(onComplete: onComplete)
                case let .candidate(candidate):
                    RecordFormView(mode: .prefilled(candidate.recordDetail()), onComplete: onComplete)
                case .manual:
                    RecordFormView(mode: .new, onComplete: onComplete)
                }
            }
    }
}

/// The camera-scanner UI. Live capture (VisionKit) is wired on device in a
/// later milestone; here the frame is tappable to simulate a detected barcode.
private struct ScannerSurface: View {
    var onClose: () -> Void

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x2A2622), Color(hex: 0x0A0A0A)],
                           center: UnitPoint(x: 0.5, y: 0.45), startRadius: 20, endRadius: 460)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.5), in: Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 20)
                Text("Scan barcode")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 4)
                Spacer()
            }
            .padding(.top, 16)

            VStack(spacing: 22) {
                NavigationLink(value: AddRoute.match) {
                    reticle
                }
                .buttonStyle(.plain)

                Text("Line up the barcode on the back cover")
                    .font(.prBody)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Tap the frame to simulate a scan")
                    .font(.prSmall)
                    .foregroundStyle(.white.opacity(0.4))
            }

            VStack {
                Spacer()
                HStack(spacing: 60) {
                    circleButton(icon: "bolt.fill", label: "Torch")
                    NavigationLink(value: AddRoute.manual) {
                        VStack(spacing: 6) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 22))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.white.opacity(0.15), in: Circle())
                            Text("Enter manually").font(.prSmall).foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 64)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var reticle: some View {
        let barWidths: [CGFloat] = [2, 1, 3, 1, 2, 4, 1, 2, 3, 1, 2]
        return ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Palette.accent, lineWidth: 3)
                .frame(width: 280, height: 170)
            Rectangle()
                .fill(Palette.accent)
                .frame(width: 232, height: 2)
                .shadow(color: Palette.accent.opacity(0.7), radius: 6)
            HStack(spacing: 6) {
                ForEach(Array(barWidths.enumerated()), id: \.offset) { pair in
                    Rectangle().fill(Color.white.opacity(0.5))
                        .frame(width: pair.element, height: 44)
                }
            }
        }
    }

    private func circleButton(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.15), in: Circle())
            Text(label).font(.prSmall).foregroundStyle(.white)
        }
    }
}

// MARK: - Match / confirm

struct MatchView: View {
    var onComplete: () -> Void
    private let candidates = PressingCandidate.sample

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "barcode")
                        .font(.system(size: 17))
                        .foregroundStyle(Palette.badgeAmberText)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("602547976598")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.badgeAmberText)
                        Text("\(candidates.count) pressings match this barcode")
                            .font(.prSmall)
                            .foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Palette.badgeAmberFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.accent.opacity(0.3)))
                .padding(.bottom, 14)

                Text("A LOVE SUPREME · JOHN COLTRANE")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Palette.tertiary)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 4)

                ForEach(candidates) { candidate in
                    NavigationLink(value: AddRoute.candidate(candidate)) {
                        CandidateRow(candidate: candidate)
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink(value: AddRoute.manual) {
                    Text("None of these — enter manually")
                        .font(.prHeadline)
                        .foregroundStyle(Palette.tint)
                        .frame(maxWidth: .infinity)
                        .padding(20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Metrics.screenPadding)
        }
        .background(Palette.background)
        .navigationTitle("Choose pressing")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CandidateRow: View {
    let candidate: PressingCandidate

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CoverArtView(seed: candidate.title, cornerRadius: 6)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(candidate.label) · \(candidate.catalogNumber)")
                        .font(.prBodyEmphasis)
                        .foregroundStyle(Palette.label)
                        .lineLimit(1)
                    Text("\(candidate.year) · \(candidate.country) · \(candidate.format)")
                        .font(.prSmall)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.quaternary)
            }
            .padding(.vertical, 12)
            HRule()
        }
    }
}

// MARK: - Text search

struct TextSearchView: View {
    var onComplete: () -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var results: [PressingCandidate] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : PressingCandidate.sample
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.tertiary)
                    TextField("Artist or album title", text: $query)
                        .font(.prBody)
                        .foregroundStyle(Palette.label)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.controlFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .padding(.bottom, 14)

                if results.isEmpty {
                    Text("Search Discogs by artist or title, then pick the exact pressing.")
                        .font(.prBody)
                        .foregroundStyle(Palette.secondary)
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(results) { candidate in
                        NavigationLink(value: AddRoute.candidate(candidate)) {
                            CandidateRow(candidate: candidate)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
        }
        .background(Palette.background)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: AddRoute.self) { route in
            switch route {
            case let .candidate(candidate):
                RecordFormView(mode: .prefilled(candidate.recordDetail()), onComplete: onComplete)
            default:
                RecordFormView(mode: .new, onComplete: onComplete)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
