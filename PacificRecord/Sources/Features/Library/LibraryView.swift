import SwiftUI
import VinylCore

struct LibraryView: View {
    @Environment(LibraryModel.self) private var model
    @State private var showAdd = false
    @State private var pendingAdd: AddChoice?
    @State private var activeAdd: AddChoice?
    @State private var showSettings = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.isEmpty {
                    EmptyLibraryView(onAdd: { showAdd = true })
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(model.count) records · \(model.artistCount) artists")
                                .font(.system(size: 15))
                                .foregroundStyle(Palette.secondary)
                                .padding(.top, 2)
                                .padding(.bottom, 14)

                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Palette.tertiary)
                                TextField("Search title, artist, label", text: $model.searchText)
                                    .font(.prBody)
                                    .foregroundStyle(Palette.label)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Palette.controlFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .onChange(of: model.searchText) { model.reload() }

                            HStack {
                                sortMenu
                                Spacer()
                                layoutToggle
                            }
                            .padding(.vertical, 14)

                            if model.records.isEmpty {
                                Text("No records match “\(model.searchText)”.")
                                    .font(.prBody)
                                    .foregroundStyle(Palette.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 48)
                            } else if model.layout == .grid {
                                LibraryGrid(records: model.records)
                            } else {
                                LibraryList(records: model.records)
                            }
                        }
                        .padding(.horizontal, Metrics.screenPadding)
                        .padding(.bottom, 28)
                    }
                }
            }
            .background(Palette.background)
            .navigationTitle("Library")
            .navigationDestination(for: String.self) { id in
                RecordDetailScreen(recordID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .accessibilityLabel("Add record")
                }
            }
            .tint(Palette.tint)
        }
        .sheet(isPresented: $showAdd, onDismiss: {
            if let choice = pendingAdd {
                pendingAdd = nil
                activeAdd = choice
            }
        }) {
            AddEntrySheet { choice in
                pendingAdd = choice
                showAdd = false
            }
        }
        .sheet(item: $activeAdd) { choice in
            AddFlowContainer(choice: choice, library: model, onFinish: { activeAdd = nil })
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }.tint(Palette.tint)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(LibraryStore.SortOrder.allCases, id: \.self) { order in
                Button {
                    model.sort = order
                    model.reload()
                } label: {
                    if model.sort == order {
                        Label(order.label, systemImage: "checkmark")
                    } else {
                        Text(order.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Sort").foregroundStyle(Palette.secondary)
                Text(model.sort.label).foregroundStyle(Palette.label)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.tint)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Palette.grouped, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)
        }
    }

    private var layoutToggle: some View {
        HStack(spacing: 0) {
            layoutButton(icon: "square.grid.2x2.fill", layout: .grid)
            layoutButton(icon: "list.bullet", layout: .list)
        }
        .padding(3)
        .background(Palette.controlFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func layoutButton(icon: String, layout: LibraryLayout) -> some View {
        let active = model.layout == layout
        return Button {
            model.layout = layout
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? Palette.label : Palette.tertiary)
                .frame(width: 34, height: 28)
                .background(
                    active ? Palette.segmentSelected : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout == .grid ? "Grid view" : "List view")
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Grid

struct LibraryGrid: View {
    let records: [Release]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 11), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(records) { release in
                NavigationLink(value: release.id) {
                    VStack(alignment: .leading, spacing: 6) {
                        CoverArtView(seed: release.coverSeed, coverPath: release.coverPath)
                            .aspectRatio(1, contentMode: .fit)
                            .shadow(color: .black.opacity(0.5), radius: 7, y: 4)
                        Text(release.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.label)
                            .lineLimit(1)
                        Text(release.artistDisplay)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.tertiary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - List

struct LibraryList: View {
    let records: [Release]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(records) { release in
                NavigationLink(value: release.id) {
                    LibraryRow(release: release)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct LibraryRow: View {
    let release: Release

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                CoverArtView(seed: release.coverSeed, coverPath: release.coverPath, cornerRadius: 6)
                    .frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(release.title)
                        .font(.prBodyEmphasis)
                        .foregroundStyle(Palette.label)
                        .lineLimit(1)
                    Text(release.listSubtitle)
                        .font(.prFootnote)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let media = release.mediaCondition {
                    GradePill(text: media.rawValue)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.quaternary)
            }
            .padding(.vertical, 9)
            HRule()
        }
    }
}

// MARK: - Empty state

struct EmptyLibraryView: View {
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(hex: 0x2A2A2C), Color(hex: 0x161618)],
                        center: UnitPoint(x: 0.5, y: 0.42),
                        startRadius: 2, endRadius: 72))
                    .overlay(Circle().strokeBorder(Palette.separator, lineWidth: 1))
                Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1).padding(44)
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 34, height: 34)
                    .shadow(color: Palette.accent.opacity(0.5), radius: 12)
            }
            .frame(width: 132, height: 132)
            .padding(.bottom, 26)

            Text("Start your collection")
                .font(.prTitle2)
                .foregroundStyle(Palette.label)
                .padding(.bottom, 10)
            Text("Scan a barcode, search by title, or add a record by hand. Your library is saved to iCloud Drive.")
                .font(.prBody)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 26)

            PrimaryButton(title: "Add your first record", action: onAdd)
            Button(action: onAdd) {
                Text("Import from Discogs")
                    .font(.prHeadline)
                    .foregroundStyle(Palette.tint)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
        .padding(.horizontal, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
