import SwiftUI
import VinylCore

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
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if model.isEmpty {
                    EmptyLibraryView(onAdd: { showAdd = true }, onImport: { showImport = true })
                } else {
                    content
                }
            }
            .background(Palette.background)
            .navigationTitle(navTitle)
            .navigationDestination(for: String.self) { id in
                RecordDetailScreen(recordID: id)
            }
            .toolbar { toolbarContent }
            .tint(Palette.tint)
            // An overlay rather than `safeAreaInset`: the inset was applied even
            // when not selecting, and it competed with SwiftUI's keyboard
            // avoidance, leaving the last rows underneath the keyboard.
            .overlay(alignment: .bottom) {
                if selecting {
                    BulkActionBar(
                        count: selectedIDs.count,
                        locations: model.locations,
                        onAssign: assignLocation,
                        onDelete: { confirmBulkDelete = true }
                    )
                    // Slide it in at full height; without a transition the
                    // material background gets rendered at zero height as the
                    // bar appears, which the render server complains about.
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

    // MARK: Main content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.count) records · \(model.artistCount) artists")
                        .font(.prNumeric)
                        .foregroundStyle(Palette.secondary)
                    if !model.totalValueByCurrency.isEmpty {
                        Text("≈ \(model.formattedTotalValue) estimated value")
                            .font(.prCaptionSm)
                            .monospacedDigit()
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 14)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
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
                    if !model.searchText.isEmpty {
                        Button {
                            model.searchText = ""
                            model.reload()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Palette.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Palette.controlFill, in: Capsule())
                .onChange(of: model.searchText) { model.reload() }

                HStack(spacing: 8) {
                    sortMenu
                    filterButton
                    Spacer()
                    layoutToggle
                }
                .padding(.vertical, 14)

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
            // Extra room so the floating bulk-action bar doesn't sit on top of
            // the last row while selecting.
            .padding(.bottom, selecting ? 96 : 28)
        }
        // Swiping the list down dismisses the keyboard — the search field is
        // inside the scroll view, so there was otherwise no way to put it away.
        .scrollDismissesKeyboard(.interactively)
        .refreshable { model.refreshAll() }
    }

    private var emptyResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 34))
                .foregroundStyle(Palette.tertiary)
            Text(emptyResultsMessage)
                .font(.prBody)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
            if model.filter.isActive {
                Button("Clear filters") { model.clearFilter() }
                    .font(.prHeadline)
                    .foregroundStyle(Palette.tint)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, 20)
    }

    private var emptyResultsMessage: String {
        let searching = !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty
        switch (searching, model.filter.isActive) {
        case (true, true): return "No records match your search and filters."
        case (true, false): return "No records match “\(model.searchText)”."
        default: return "No records match the current filters."
        }
    }

    // MARK: Toolbar

    private var navTitle: String {
        guard selecting else { return "Library" }
        return selectedIDs.isEmpty ? "Select records" : "\(selectedIDs.count) selected"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { exitSelection() }.fontWeight(.semibold)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(allSelected ? "Deselect All" : "Select All") { toggleSelectAll() }
                    .disabled(model.visibleRecords.isEmpty)
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { enterSelection() } label: { Image(systemName: "checkmark.circle") }
                    .accessibilityLabel("Select records")
                Button { showAdd = true } label: { Image(systemName: "plus").fontWeight(.semibold) }
                    .accessibilityLabel("Add record")
            }
        }
        // Always reachable way to put the keyboard away.
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
        searchFocused = false   // the keyboard has no place in selection mode
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

    // MARK: Sort / filter / layout

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
                Text(model.sort.label.uppercased())
                    .font(.prCaption)
                    .tracking(Metrics.overlineTracking)
                    .foregroundStyle(Palette.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Palette.fill, in: Capsule())
        }
        .accessibilityLabel("Sort by \(model.sort.label)")
    }

    private var filterButton: some View {
        Button { showFilter = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11, weight: .semibold))
                Text("Filter".uppercased())
                    .font(.prCaption)
                    .tracking(Metrics.overlineTracking)
                if model.filter.activeCount > 0 {
                    Text("\(model.filter.activeCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.onPrimary)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Palette.accent, in: Circle())
                }
            }
            .foregroundStyle(model.filter.isActive ? Palette.accent : Palette.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Palette.fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.filter.activeCount > 0 ? "Filter, \(model.filter.activeCount) active" : "Filter")
    }

    private var layoutToggle: some View {
        HStack(spacing: 0) {
            layoutButton(icon: "square.grid.2x2.fill", layout: .grid)
            layoutButton(icon: "list.bullet", layout: .list)
        }
        .padding(3)
        .background(Palette.controlFill, in: Capsule())
    }

    private func layoutButton(icon: String, layout: LibraryLayout) -> some View {
        let active = model.layout == layout
        return Button {
            model.layout = layout
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Palette.label : Palette.tertiary)
                .frame(width: 34, height: 26)
                .background(active ? Palette.segmentSelected : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout == .grid ? "Grid view" : "List view")
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
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
                .font(.prFootnote)
                .foregroundStyle(Palette.secondary)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 4)
        // Extends the blur behind the home indicator; as an overlay (rather
        // than a safe-area inset) the bar sits inside the safe area.
        .background {
            Rectangle().fill(Palette.chrome).ignoresSafeArea(edges: .bottom)
        }
        // A hairline, not a shadow.
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 11), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
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
        VStack(alignment: .leading, spacing: 6) {
            CoverArtView(seed: release.coverSeed, coverPath: release.listCoverPath, maxPixel: CoverSize.tile)
                .aspectRatio(1, contentMode: .fit)
                // Artwork is separated by value, not by a drop shadow.
                .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                            .strokeBorder(Palette.accent, lineWidth: 3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if selecting { SelectionBadge(selected: selected) }
                }
                .opacity(selecting && !selected ? 0.72 : 1)
            Text(release.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.label)
                .lineLimit(1)
            Text(release.artistDisplay)
                .font(.prCaptionSm)
                .foregroundStyle(Palette.tertiary)
                .lineLimit(1)
        }
    }
}

struct SelectionBadge: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle().fill(selected ? Palette.accent : Color.black.opacity(0.4))
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
            HStack(spacing: 13) {
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? Palette.accent : Palette.quaternary)
                }
                CoverArtView(seed: release.coverSeed, coverPath: release.listCoverPath,
                             cornerRadius: Metrics.tileRadius, maxPixel: CoverSize.row)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
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
                VStack(alignment: .trailing, spacing: 4) {
                    if showValue, let value = release.formattedValue {
                        Text(value)
                            .font(.prNumeric)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                    if let media = release.mediaCondition {
                        GradePill(text: media.rawValue)
                    }
                }
                if !selecting {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.quaternary)
                }
            }
            .padding(.vertical, 9)
            HRule()
        }
    }
}

// MARK: - Empty state

struct EmptyLibraryView: View {
    var onAdd: () -> Void
    var onImport: () -> Void

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
            Text("Scan a barcode, search by title, or add a record by hand. Your library is saved on this iPhone.")
                .font(.prBody)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 26)

            PrimaryButton(title: "Add your first record", action: onAdd)
            Button(action: onImport) {
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
