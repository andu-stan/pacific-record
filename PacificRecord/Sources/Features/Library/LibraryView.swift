import SwiftUI
import VinylCore

/// The Library screen, built to the "Vinyl Library" design: an in-content
/// header (settings / select / add), a serif display title, a row of stat
/// cards, a pill control strip, and either a 3-up cover grid or a list.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var model
    @State private var showAdd = false
    @State private var pendingAdd: AddChoice?
    @State private var activeAdd: AddChoice?
    @State private var showSettings = false
    @State private var showFilter = false
    @State private var showImport = false
    @State private var pendingImport = false
    @State private var selecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var confirmBulkDelete = false
    @State private var searchOpen = false
    @FocusState private var searchFocused: Bool
    /// Explicit path so a widget tap can push a record.
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            // The header sits outside the branch so Settings and Add stay
            // reachable when the library is empty — otherwise a fresh install
            // has no route to the Discogs token or to restoring a backup.
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Metrics.screenPadding)
                if model.isEmpty {
                    EmptyLibraryView(
                        onAdd: { showAdd = true },
                        onImport: { showImport = true },
                        onSettings: { showSettings = true }
                    )
                } else {
                    content
                }
            }
            .background(Palette.background)
            .navigationBarTitleDisplayMode(.inline)
            // The design carries the title and its actions in the content, so
            // the system bar is hidden on the root screen.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                RecordDetailScreen(recordID: id)
            }
            // Tapping "Record of the Day" opens that record.
            .onOpenURL { url in
                if let id = WidgetDeepLink.recordID(from: url), model.detail(id: id) != nil {
                    path = [id]
                }
            }
            .toolbar { keyboardToolbar }
            .tint(Palette.tint)
            .overlay(alignment: .bottom) {
                if selecting {
                    BulkActionBar(
                        count: selectedIDs.count,
                        locations: model.locations,
                        onAssign: assignLocation,
                        onDelete: { confirmBulkDelete = true }
                    )
                    .transition(.move(edge: .bottom))
                }
            }
            .confirmationDialog(bulkDeleteTitle, isPresented: $confirmBulkDelete, titleVisibility: .visible) {
                Button("Delete \(selectedIDs.count == 1 ? "record" : "\(selectedIDs.count) records")", role: .destructive) {
                    performBulkDelete()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: {
            if let choice = pendingAdd {
                pendingAdd = nil
                activeAdd = choice
            } else if pendingImport {
                pendingImport = false
                showImport = true
            }
        }) {
            AddEntrySheet(
                onSelect: { choice in
                    pendingAdd = choice
                    showAdd = false
                },
                onImportCollection: {
                    pendingImport = true
                    showAdd = false
                }
            )
        }
        .sheet(item: $activeAdd) { choice in
            AddFlowContainer(choice: choice, library: model, onFinish: { activeAdd = nil })
        }
        .sheet(isPresented: $showImport) {
            DiscogsImportView()
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }.tint(Palette.tint)
        }
        .sheet(isPresented: $showFilter) {
            NavigationStack { LibraryFilterView() }
                .tint(Palette.tint)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(selecting ? selectionTitle : model.displayName)
                    .font(.prDisplay)
                    .tracking(-0.8)
                    .foregroundStyle(Palette.label)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)

                statCards
                if searchOpen { searchField }
                controlStrip

                if model.visibleRecords.isEmpty {
                    emptyResults
                } else if model.layout == .grid {
                    LibraryGrid(records: model.visibleRecords, selecting: selecting,
                                selectedIDs: selectedIDs, onToggle: toggle)
                } else {
                    LibraryList(records: model.visibleRecords, selecting: selecting,
                                selectedIDs: selectedIDs, onToggle: toggle)
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, selecting ? 96 : 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { model.refreshAll() }
    }

    /// Settings on the left; a pill group carrying Select and Add on the right.
    private var header: some View {
        HStack(spacing: 0) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(.leading, -10)
            .accessibilityLabel("Settings")

            Spacer()

            HStack(spacing: 4) {
                // Nothing to select in an empty library.
                if !model.isEmpty {
                    Button { selecting ? exitSelection() : enterSelection() } label: {
                        Text(selecting ? "Done" : "Select")
                            .font(.prCaption)
                            .tracking(Metrics.overlineTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(selecting ? Palette.label : Palette.secondary)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    if selecting { toggleSelectAll() } else { showAdd = true }
                } label: {
                    Image(systemName: selecting ? (allSelected ? "minus" : "checkmark") : "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.onPrimary)
                        .frame(width: 36, height: 36)
                        .background(Palette.primaryFill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selecting ? (allSelected ? "Deselect all" : "Select all") : "Add record")
            }
            .padding(4)
            .background(Palette.fill, in: Capsule())
        }
        .frame(height: 48)
        .padding(.bottom, 8)
    }

    private var selectionTitle: String {
        selectedIDs.isEmpty ? "Select" : "\(selectedIDs.count) selected"
    }

    /// Records · Artists · Genres, all reflecting the current filter.
    private var statCards: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statCard(icon: "opticaldisc", value: model.count, label: "Records")
                statCard(icon: "music.mic", value: model.artistCount, label: "Artists")
                statCard(icon: "guitars", value: model.genreCount, label: "Genres")
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    /// Stat card per the design system: a light-stroke icon at
    /// `--text-secondary`, then the value over its overline label.
    private func statCard(icon: String, value: Int, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Palette.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.prStatValue)
                    .tracking(-0.5)
                    .foregroundStyle(Palette.label)
                    // Three cards across an iPhone leaves little room, so a
                    // five-figure count shrinks rather than wrapping.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(label.uppercased())
                    .font(.prCaption)
                    .tracking(Metrics.overlineTracking)
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Palette.tertiary)
            TextField("Search title, artist, label",
                      text: Binding(get: { model.searchText }, set: { model.searchText = $0 }))
                .font(.prBody)
                .foregroundStyle(Palette.label)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .onChange(of: model.searchText) { model.reload() }
            Button {
                model.searchText = ""
                model.reload()
                searchFocused = false
                withAnimation(.easeInOut(duration: 0.2)) { searchOpen = false }
            } label: {
                Text("Clear")
                    .font(.prCaption)
                    .tracking(Metrics.overlineTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.grouped, in: Capsule())
        .padding(.bottom, 12)
    }

    /// Search toggle, sort, filter, and the grid/list segmented control.
    private var controlStrip: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { searchOpen.toggle() }
                searchFocused = searchOpen
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(searchOpen ? Palette.onPrimary : Palette.secondary)
                    .frame(width: 28, height: 28)
                    .background(searchOpen ? Palette.primaryFill : Palette.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")

            sortPill
            filterPill

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                layoutButton(icon: "square.grid.2x2", layout: .grid)
                layoutButton(icon: "list.bullet", layout: .list)
            }
            .padding(3)
            .background(Palette.grouped, in: Capsule())
        }
        .padding(.bottom, 16)
    }

    private var sortPill: some View {
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
            Text("Sort · \(model.sort.label)".uppercased())
                .font(.prCaption)
                .tracking(Metrics.overlineTracking)
                .foregroundStyle(Palette.label)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Palette.fill, in: Capsule())
        }
        .accessibilityLabel("Sort by \(model.sort.label)")
    }

    private var filterPill: some View {
        Button { showFilter = true } label: {
            HStack(spacing: 6) {
                Text(model.filter.isActive ? "Filtered" : "Filter")
                    .font(.prCaption)
                    .tracking(Metrics.overlineTracking)
                    .textCase(.uppercase)
                if model.filter.activeCount > 0 {
                    Text("\(model.filter.activeCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(model.filter.isActive ? Palette.onPrimary : Palette.secondary)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(model.filter.isActive ? Palette.primaryFill : Palette.fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func layoutButton(icon: String, layout: LibraryLayout) -> some View {
        let active = model.layout == layout
        return Button {
            model.layout = layout
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Palette.label : Palette.tertiary)
                .frame(width: 34, height: 28)
                .background(active ? Palette.segmentSelected : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout == .grid ? "Grid view" : "List view")
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    private var emptyResults: some View {
        VStack(spacing: 12) {
            Text(emptyResultsMessage)
                .font(.prSmall)
                .foregroundStyle(Palette.tertiary)
                .multilineTextAlignment(.center)
            if model.filter.isActive {
                Button { model.clearFilter() } label: {
                    Text("Clear filters")
                        .font(.prCaption)
                        .tracking(Metrics.overlineTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var emptyResultsMessage: String {
        let query = model.searchText.trimmingCharacters(in: .whitespaces)
        switch (query.isEmpty, model.filter.isActive) {
        case (false, true): return "Nothing matches “\(query)” with these filters."
        case (false, false): return "Nothing matches “\(query)”."
        default: return "Nothing matches the current filters."
        }
    }

    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { searchFocused = false }
        }
    }

    // MARK: Selection

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private var allSelected: Bool {
        let visible = model.visibleRecords
        return !visible.isEmpty && visible.allSatisfy { selectedIDs.contains($0.id) }
    }

    private func toggleSelectAll() {
        let visible = model.visibleRecords.map(\.id)
        if allSelected { selectedIDs.subtract(visible) } else { selectedIDs.formUnion(visible) }
    }

    private func enterSelection() {
        searchFocused = false
        selectedIDs = []
        withAnimation(.easeInOut(duration: 0.2)) { selecting = true }
    }

    private func exitSelection() {
        withAnimation(.easeInOut(duration: 0.2)) { selecting = false }
        selectedIDs = []
    }

    private func assignLocation(_ locationID: String?) {
        model.setLocation(locationID, for: selectedIDs)
        Haptics.success()
        exitSelection()
    }

    private var bulkDeleteTitle: String {
        selectedIDs.count == 1 ? "Delete this record?" : "Delete \(selectedIDs.count) records?"
    }

    private func performBulkDelete() {
        model.delete(ids: selectedIDs)
        Haptics.success()
        exitSelection()
    }
}

// MARK: - Bulk action bar

struct BulkActionBar: View {
    let count: Int
    let locations: [Location]
    var onAssign: (String?) -> Void
    var onDelete: () -> Void

    private var disabled: Bool { count == 0 }

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                Button { onAssign(nil) } label: { Label("No location", systemImage: "mappin.slash") }
                if !locations.isEmpty {
                    Divider()
                    ForEach(locations) { location in
                        Button { onAssign(location.id) } label: { Text(location.name) }
                    }
                }
            } label: {
                barLabel(icon: "mappin.and.ellipse", title: "Location", tint: Palette.tint)
            }
            .disabled(disabled)

            Button { onDelete() } label: {
                barLabel(icon: "trash", title: "Delete", tint: Palette.danger)
            }
            .buttonStyle(.plain)
            .disabled(disabled)

            Spacer()

            Text(count == 0 ? "Nothing selected" : "\(count) selected")
                .font(.prCaptionSm)
                .monospacedDigit()
                .foregroundStyle(Palette.secondary)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background {
            Rectangle().fill(Palette.chrome).ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) { Rectangle().fill(Palette.separator).frame(height: 1) }
    }

    private func barLabel(icon: String, title: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 17, weight: .regular))
            Text(title.uppercased())
                .font(.prCaption)
                .tracking(Metrics.overlineTracking)
        }
        .foregroundStyle(disabled ? Palette.quaternary : tint)
        .frame(minWidth: 62)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Grid

struct LibraryGrid: View {
    let records: [Release]
    var selecting: Bool = false
    var selectedIDs: Set<String> = []
    var onToggle: (String) -> Void = { _ in }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(records) { release in
                if selecting {
                    Button { onToggle(release.id) } label: {
                        cell(release, selected: selectedIDs.contains(release.id))
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(value: release.id) {
                        cell(release, selected: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func cell(_ release: Release, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverArtView(seed: release.coverSeed, coverPath: release.listCoverPath, maxPixel: CoverSize.tile)
                .aspectRatio(1, contentMode: .fit)
                // The pressing year sits quietly in the corner of the sleeve.
                .overlay(alignment: .bottomLeading) {
                    if let year = release.year, !selecting {
                        Text(String(year))
                            .font(.prMonoTiny)
                            .tracking(0.4)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 3))
                            .padding(6)
                    }
                }
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                            .strokeBorder(Palette.accent, lineWidth: 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if selecting { SelectionBadge(selected: selected) }
                }
                .opacity(selecting && !selected ? 0.72 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(release.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                Text(release.artistDisplay)
                    .font(.prCaptionSm)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct SelectionBadge: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle().fill(selected ? Palette.accent : Color.black.opacity(0.45))
            Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
        .padding(6)
    }
}

// MARK: - List

struct LibraryList: View {
    let records: [Release]
    var selecting: Bool = false
    var selectedIDs: Set<String> = []
    var onToggle: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(records) { release in
                if selecting {
                    Button { onToggle(release.id) } label: {
                        LibraryRow(release: release, selecting: true, selected: selectedIDs.contains(release.id))
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(value: release.id) {
                        LibraryRow(release: release)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct LibraryRow: View {
    let release: Release
    var selecting: Bool = false
    var selected: Bool = false

    @AppStorage(RecordValueService.showValueInListKey) private var showValue = false

    var body: some View {
        VStack(spacing: 0) {
            // Rows are divided by a rule above them, per the design.
            Rectangle().fill(Palette.separator).frame(height: 1)
            HStack(spacing: 16) {
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? Palette.accent : Palette.quaternary)
                }
                CoverArtView(seed: release.coverSeed, coverPath: release.listCoverPath,
                             cornerRadius: Metrics.tileRadius, maxPixel: CoverSize.row)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 0) {
                    Text(release.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.label)
                        .lineLimit(1)
                    Text(release.listSubtitle)
                        .font(.prSmall)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    if showValue, let value = release.formattedValue {
                        Text(value)
                            .font(.prCaptionSm)
                            .monospacedDigit()
                            .foregroundStyle(Palette.tertiary)
                    }
                    if let format = release.formatBadge {
                        Text(format)
                            .font(.prMonoSmall)
                            .foregroundStyle(Palette.tertiary)
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Empty state

struct EmptyLibraryView: View {
    var onAdd: () -> Void
    var onImport: () -> Void
    var onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Library")
                .font(.prDisplay)
                .tracking(-0.8)
                .foregroundStyle(Palette.label)
                .padding(.bottom, 12)
            Text("Scan a barcode, search by title, or add a record by hand. Your library is saved on this iPhone.")
                .font(.prBody)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)

            PrimaryButton(title: "Add your first record", action: onAdd)

            // A fresh install lands here, so the two ways of arriving with a
            // collection already in hand need to be reachable from this screen.
            VStack(spacing: 16) {
                Button(action: onImport) { linkLabel("Import from Discogs") }
                    .buttonStyle(.plain)
                Button(action: onSettings) { linkLabel("Restore a backup") }
                    .buttonStyle(.plain)
            }
            .padding(.top, 20)

            Text("Settings is where you add a Discogs token and restore an exported library.")
                .font(.prSmall)
                .foregroundStyle(Palette.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 24)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func linkLabel(_ text: String) -> some View {
        Text(text)
            .font(.prCaption)
            .tracking(Metrics.overlineTracking)
            .textCase(.uppercase)
            .foregroundStyle(Palette.tint)
    }
}
