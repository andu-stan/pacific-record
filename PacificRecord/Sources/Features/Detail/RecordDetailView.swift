import SwiftUI
import VinylCore

/// A record's persisted value, formatted for display.
struct StoredValue: Equatable {
    var amount: Double
    var currency: String
    var basis: String
    var date: Date?

    init(amount: Double, currency: String, basis: String, date: Date?) {
        self.amount = amount
        self.currency = currency
        self.basis = basis
        self.date = date
    }

    init?(release: Release) {
        guard let amount = release.estimatedValue, let currency = release.valueCurrency else { return nil }
        self.amount = amount
        self.currency = currency
        self.basis = release.valueBasis ?? ""
        self.date = release.valueUpdatedAt
    }

    var formattedAmount: String {
        amount.formatted(.currency(code: currency))
    }

    /// "Near Mint copy" / "Lowest listing" for the subtitle.
    var basisLabel: String {
        if let condition = Condition(rawValue: basis) {
            return "\(condition.displayName) copy"
        }
        return basis
    }
}

struct RecordDetailScreen: View {
    let recordID: String
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var estimate: StoredValue?
    @State private var isEstimating = false
    @State private var didLoadEstimate = false

    var body: some View {
        Group {
            if let detail = model.detail(id: recordID) {
                RecordDetailContent(
                    detail: detail,
                    value: estimate,
                    isEstimating: isEstimating,
                    canEstimate: detail.release.discogsReleaseID != nil,
                    locationName: model.location(id: detail.release.locationID)?.name,
                    onEstimate: { estimateValue(detail.release) },
                    onDelete: { confirmDelete = true }
                )
                .onAppear {
                    if !didLoadEstimate {
                        estimate = StoredValue(release: detail.release)
                        didLoadEstimate = true
                    }
                }
                .sheet(isPresented: $showEdit) {
                    NavigationStack { RecordFormView(mode: .edit(detail)) }
                        .tint(Palette.tint)
                }
                .confirmationDialog("Delete this record?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete record", role: .destructive) {
                        model.delete(detail.release)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } else {
                Text("Record not found.")
                    .font(.prBody)
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
            }
        }
        .tint(Palette.tint)
    }

    private func estimateValue(_ release: Release) {
        guard !isEstimating else { return }
        isEstimating = true
        Task {
            if let result = await RecordValueService.fetch(for: release) {
                model.setValue(amount: result.amount, currency: result.currency, basis: result.basis, for: release)
                estimate = StoredValue(amount: result.amount, currency: result.currency, basis: result.basis, date: Date())
                Haptics.success()
            } else {
                Haptics.warning()
            }
            isEstimating = false
        }
    }
}

struct RecordDetailContent: View {
    let detail: RecordDetail
    var value: StoredValue?
    var isEstimating: Bool
    var canEstimate: Bool
    var locationName: String? = nil
    var onEstimate: () -> Void
    var onDelete: () -> Void

    @State private var showCover = false

    private var release: Release { detail.release }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                CoverArtView(seed: release.coverSeed, coverPath: release.coverPath, cornerRadius: 12)
                    .frame(width: 236, height: 236)
                    .shadow(color: .black.opacity(0.85), radius: 30, y: 24)
                    .padding(.top, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { showCover = true }
                    .accessibilityElement()
                    .accessibilityLabel("Cover — tap to view full screen")
                    .accessibilityAddTraits(.isButton)

                Text(release.title)
                    .font(.prTitle)
                    .foregroundStyle(Palette.label)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                Text(release.artistDisplay)
                    .font(.system(size: 19))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 2)
                StarRatingView(rating: release.rating, size: 18)
                    .padding(.top, 10)

                VStack(spacing: 16) {
                    infoCard
                    conditionCards
                    if value != nil || canEstimate { valueSection }
                    if !detail.tracks.isEmpty { tracklist }
                    if let notes = release.notes, !notes.isEmpty { notesCard(notes) }
                    deleteButton
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 30)
        }
        .fullScreenCover(isPresented: $showCover) {
            CoverViewer(seed: release.coverSeed, coverPath: release.coverPath)
        }
    }

    // MARK: Info card

    private var infoPairs: [(String, String)] {
        var pairs: [(String, String)] = []
        if let label = detail.labels.first {
            pairs.append(("Label", label.name))
            if let catalog = label.catalogNumber { pairs.append(("Catalog no.", catalog)) }
        }
        if !release.yearCountryLine.isEmpty { pairs.append(("Year · Country", release.yearCountryLine)) }
        if !release.formatLine.isEmpty { pairs.append(("Format", release.formatLine)) }
        if !release.genreLine.isEmpty { pairs.append(("Genre", release.genreLine)) }
        if let locationName, !locationName.isEmpty { pairs.append(("Location", locationName)) }
        return pairs
    }

    private var infoCard: some View {
        GroupedCard {
            VStack(spacing: 0) {
                ForEach(Array(infoPairs.enumerated()), id: \.offset) { index, pair in
                    InfoRow(label: pair.0, value: pair.1, showsDivider: index < infoPairs.count - 1)
                }
            }
        }
    }

    // MARK: Condition

    private var conditionCards: some View {
        HStack(spacing: 12) {
            conditionCard(title: "Media", condition: release.mediaCondition)
            conditionCard(title: "Sleeve", condition: release.sleeveCondition)
        }
    }

    private func conditionCard(title: String, condition: Condition?) -> some View {
        GroupedCard(radius: 14, padding: EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Palette.tertiary)
                if let condition {
                    ConditionBadge(condition: condition, fontSize: 15)
                } else {
                    Text("—").font(.prBodyEmphasis).foregroundStyle(Palette.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Value

    private var valueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Value")
                .font(.prSection)
                .foregroundStyle(Palette.label)
            GroupedCard(radius: 14, padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                if let value {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("≈ \(value.formattedAmount)")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Palette.label)
                            Text(valueSubtitle(value))
                                .font(.prSmall)
                                .foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        Button(action: onEstimate) {
                            if isEstimating {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Palette.tint)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isEstimating)
                        .accessibilityLabel("Refresh value")
                    }
                } else {
                    Button(action: onEstimate) {
                        HStack(spacing: 8) {
                            if isEstimating {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "dollarsign.circle")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            Text(isEstimating ? "Fetching…" : "Estimate value from Discogs")
                                .font(.prBodyEmphasis)
                            Spacer()
                        }
                        .foregroundStyle(Palette.tint)
                    }
                    .buttonStyle(.plain)
                    .disabled(isEstimating)
                }
            }
        }
    }

    private func valueSubtitle(_ value: StoredValue) -> String {
        var parts = [value.basisLabel, "Discogs"]
        if let date = value.date {
            parts.append("updated " + date.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Tracklist

    private var sides: [(name: String, tracks: [Track])] {
        var order: [String] = []
        var map: [String: [Track]] = [:]
        for track in detail.tracks {
            let key = track.side ?? track.position.flatMap { $0.first.map(String.init) } ?? "•"
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(track)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private var tracklist: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tracklist")
                .font(.prSection)
                .foregroundStyle(Palette.label)
                .padding(.bottom, 2)
            ForEach(sides, id: \.name) { side in
                Text("SIDE \(side.name)")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Palette.tint)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 2)
                GroupedCard(radius: 14, padding: EdgeInsets(top: 2, leading: 14, bottom: 2, trailing: 14)) {
                    VStack(spacing: 0) {
                        ForEach(Array(side.tracks.enumerated()), id: \.element.id) { index, track in
                            HStack(spacing: 12) {
                                Text(track.position ?? "")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.quaternary)
                                    .frame(width: 22, alignment: .leading)
                                Text(track.title)
                                    .font(.prBody)
                                    .foregroundStyle(Palette.label)
                                Spacer(minLength: 8)
                                Text(track.durationText)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Palette.tertiary)
                            }
                            .padding(.vertical, 11)
                            if index < side.tracks.count - 1 { HRule() }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Notes / delete

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notes")
                .font(.prSection)
                .foregroundStyle(Palette.label)
                .padding(.bottom, 8)
            GroupedCard(radius: 14, padding: EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)) {
                Text(notes)
                    .font(.prBody)
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text("Delete record")
            }
            .font(.prBodyEmphasis)
            .foregroundStyle(Palette.danger)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .buttonStyle(.plain)
    }
}
