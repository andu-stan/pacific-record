import SwiftUI
import VinylCore

/// The library filter sheet: narrow the list by location, genre, format,
/// condition, and minimum rating. Edits `LibraryModel.filter` live.
struct LibraryFilterView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupedCard(radius: 14) {
                    VStack(spacing: 0) {
                        locationRow
                        HRule()
                        genreRow
                        HRule()
                        formatRow
                        HRule()
                        conditionRow
                        HRule()
                        syncRow
                    }
                }
                ratingSection
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 10)
        }
        .background(Palette.background)
        .navigationTitle("Filter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Clear") { model.filter = LibraryFilter() }
                    .disabled(!model.filter.isActive)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
        }
    }

    // MARK: Rows

    private var locationRow: some View {
        menuRow("Location", value: locationValue) {
            checkItem("Any", isOn: model.filter.location == .any) { model.filter.location = .any }
            checkItem("Unassigned", isOn: model.filter.location == .unassigned) { model.filter.location = .unassigned }
            if !model.locations.isEmpty {
                Divider()
                ForEach(model.locations) { location in
                    checkItem(location.name, isOn: model.filter.location == .location(location.id)) {
                        model.filter.location = .location(location.id)
                    }
                }
            }
        }
    }

    private var genreRow: some View {
        menuRow("Genre", value: model.filter.genre ?? "Any") {
            checkItem("Any", isOn: model.filter.genre == nil) { model.filter.genre = nil }
            if !model.availableGenres.isEmpty {
                Divider()
                ForEach(model.availableGenres, id: \.self) { genre in
                    checkItem(genre, isOn: model.filter.genre == genre) { model.filter.genre = genre }
                }
            }
        }
    }

    private var formatRow: some View {
        menuRow("Format", value: model.filter.format ?? "Any") {
            checkItem("Any", isOn: model.filter.format == nil) { model.filter.format = nil }
            if !model.availableFormats.isEmpty {
                Divider()
                ForEach(model.availableFormats, id: \.self) { format in
                    checkItem(format, isOn: model.filter.format == format) { model.filter.format = format }
                }
            }
        }
    }

    private var conditionRow: some View {
        menuRow("Media condition", value: model.filter.mediaCondition?.displayName ?? "Any") {
            checkItem("Any", isOn: model.filter.mediaCondition == nil) { model.filter.mediaCondition = nil }
            Divider()
            ForEach(Condition.allCases, id: \.self) { condition in
                checkItem(condition.displayName, isOn: model.filter.mediaCondition == condition) {
                    model.filter.mediaCondition = condition
                }
            }
        }
    }

    private var syncRow: some View {
        menuRow("Discogs", value: syncValue) {
            checkItem("Any", isOn: model.filter.sync == .any) { model.filter.sync = .any }
            checkItem("Synced", isOn: model.filter.sync == .synced) { model.filter.sync = .synced }
            checkItem("Not synced", isOn: model.filter.sync == .notSynced) { model.filter.sync = .notSynced }
        }
    }

    private var syncValue: String {
        switch model.filter.sync {
        case .any: return "Any"
        case .synced: return "Synced"
        case .notSynced: return "Not synced"
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "Minimum rating")
            HStack(spacing: 8) {
                ratingChip("Any", isOn: model.filter.minRating == 0) { model.filter.minRating = 0 }
                ForEach(1...5, id: \.self) { value in
                    ratingChip("\(value)", star: true, isOn: model.filter.minRating == value) {
                        model.filter.minRating = value
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private var locationValue: String {
        switch model.filter.location {
        case .any: return "Any"
        case .unassigned: return "Unassigned"
        case let .location(id): return model.location(id: id)?.name ?? "Unknown"
        }
    }

    private func menuRow<Content: View>(_ title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack {
                Text(title).font(.prBody).foregroundStyle(Palette.label)
                Spacer()
                Text(value)
                    .font(.prBody)
                    .foregroundStyle(value == "Any" ? Palette.tertiary : Palette.accent)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func checkItem(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isOn {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func ratingChip(_ title: String, star: Bool = false, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(title)
                if star { Image(systemName: "star.fill").font(.system(size: 9)) }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isOn ? .white : Palette.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(isOn ? Palette.accent : Palette.fill,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
