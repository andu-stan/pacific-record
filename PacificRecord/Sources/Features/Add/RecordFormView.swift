import SwiftUI
import VinylCore

enum FormMode {
    case new
    case prefilled(RecordDetail)
    case edit(RecordDetail)

    var navTitle: String {
        if case .edit = self { return "Edit Record" }
        return "New Record"
    }

    var initialDetail: RecordDetail? {
        switch self {
        case .new: return nil
        case let .prefilled(detail), let .edit(detail): return detail
        }
    }

    var editingID: String? {
        if case let .edit(detail) = self { return detail.release.id }
        return nil
    }
}

struct RecordFormView: View {
    let mode: FormMode
    var onComplete: (() -> Void)?

    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.libraryFolderURL) private var libraryFolder

    @State private var title: String
    @State private var artist: String
    @State private var label: String
    @State private var catalog: String
    @State private var yearText: String
    @State private var country: String
    @State private var tags: [String]
    @State private var format: String
    @State private var speed: String
    @State private var media: Condition?
    @State private var sleeve: Condition?
    @State private var rating: Int
    @State private var notes: String
    @State private var coverPath: String?
    @State private var thumbPath: String?
    @State private var locationID: String?
    @State private var newStyle = ""
    @State private var showAddStyle = false
    @State private var isFetchingCover = false
    @State private var coverCandidates: [CoverCandidate] = []
    @State private var coverFileID = ""
    @State private var showCoverChooser = false
    @State private var showAddLocation = false
    @State private var newLocationName = ""
    @State private var locationInitialized = false

    init(mode: FormMode, onComplete: (() -> Void)? = nil) {
        self.mode = mode
        self.onComplete = onComplete
        let detail = mode.initialDetail
        let release = detail?.release
        _title = State(initialValue: release?.title ?? "")
        _artist = State(initialValue: release?.artistDisplay ?? detail?.artists.first?.name ?? "")
        _label = State(initialValue: detail?.labels.first?.name ?? "")
        _catalog = State(initialValue: detail?.labels.first?.catalogNumber ?? "")
        _yearText = State(initialValue: release?.year.map(String.init) ?? "")
        _country = State(initialValue: release?.country ?? "")
        _tags = State(initialValue: release.map { [$0.genre].compactMap { $0 } + $0.styles } ?? [])
        _format = State(initialValue: release?.format ?? "LP")
        _speed = State(initialValue: release?.speed ?? "33⅓")
        _media = State(initialValue: release?.mediaCondition)
        _sleeve = State(initialValue: release?.sleeveCondition)
        _rating = State(initialValue: release?.rating ?? 0)
        _notes = State(initialValue: release?.notes ?? "")
        _coverPath = State(initialValue: release?.coverPath)
        _thumbPath = State(initialValue: release?.thumbPath)
        _locationID = State(initialValue: release?.locationID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                coverHeader
                infoCard
                stylesSection
                formatSpeed
                locationSection
                conditionSection
                ratingCard
                notesCard
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 8)
        }
        .background(Palette.background)
        .navigationTitle(mode.navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Preselect the default location for a record being added (not one
            // already saved), and only once so a deliberate "None" choice sticks.
            if !locationInitialized {
                locationInitialized = true
                if mode.editingID == nil, locationID == nil {
                    locationID = model.defaultLocation?.id
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty ||
                              artist.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .alert("Add style", isPresented: $showAddStyle) {
            TextField("Style", text: $newStyle)
            Button("Add") {
                let value = newStyle.trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { tags.append(value) }
                newStyle = ""
            }
            Button("Cancel", role: .cancel) { newStyle = "" }
        }
        .alert("New location", isPresented: $showAddLocation) {
            TextField("Name", text: $newLocationName)
            Button("Add") {
                if let created = model.addLocation(newLocationName) { locationID = created.id }
                newLocationName = ""
            }
            Button("Cancel", role: .cancel) { newLocationName = "" }
        } message: {
            Text("A shelf, a room, a house — anywhere records live.")
        }
        .sheet(isPresented: $showCoverChooser) {
            if let folder = libraryFolder {
                CoverChooserSheet(
                    candidates: coverCandidates,
                    seed: title.isEmpty ? artist : title,
                    fileID: coverFileID,
                    folder: folder
                ) { newCoverPath, newThumbPath in
                    coverPath = newCoverPath
                    thumbPath = newThumbPath
                }
            }
        }
    }

    // MARK: Sections

    private var coverHeader: some View {
        Button(action: replaceCover) {
            HStack(spacing: 16) {
                ZStack {
                    CoverArtView(seed: title.isEmpty ? artist : title, coverPath: coverPath, cornerRadius: 10)
                        .frame(width: 88, height: 88)
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 6)
                    if isFetchingCover {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.black.opacity(0.45))
                            .frame(width: 88, height: 88)
                        ProgressView().tint(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isFetchingCover ? "Finding covers…" : "Choose cover art")
                        .font(.prBodyEmphasis).foregroundStyle(Palette.tint)
                    Text("Pick from Apple Music, Cover Art Archive & Discogs")
                        .font(.prSmall).foregroundStyle(Palette.tertiary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(isFetchingCover)
    }

    /// Looks up every available cover for the current fields and opens the
    /// chooser grid. A warning haptic fires if nothing is found.
    private func replaceCover() {
        let artistText = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleText = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(titleText.isEmpty && artistText.isEmpty), libraryFolder != nil, !isFetchingCover else { return }
        isFetchingCover = true
        let base = mode.initialDetail?.release
        Task {
            let candidates = await CoverArtResolver.candidates(
                artist: artistText,
                title: titleText,
                barcode: base?.barcode,
                musicbrainzMBID: base?.musicbrainzMBID,
                discogsReleaseID: base?.discogsReleaseID)
            isFetchingCover = false
            if candidates.isEmpty {
                Haptics.warning()
            } else {
                coverCandidates = candidates
                coverFileID = "\(base?.id ?? UUID().uuidString)-\(Int(Date().timeIntervalSince1970))"
                showCoverChooser = true
            }
        }
    }

    private var infoCard: some View {
        GroupedCard(radius: 14) {
            VStack(spacing: 0) {
                fieldRow("Artist", $artist)
                fieldRow("Title", $title)
                fieldRow("Label", $label)
                fieldRow("Catalog no.", $catalog)
                HStack {
                    Text("Year · Country").font(.prBody).foregroundStyle(Palette.secondary)
                    Spacer(minLength: 8)
                    TextField("1959", text: $yearText)
                        .font(.prBodyEmphasis).foregroundStyle(Palette.label)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .frame(width: 56)
                    Text("·").foregroundStyle(Palette.tertiary)
                    TextField("US", text: $country)
                        .font(.prBodyEmphasis).foregroundStyle(Palette.label)
                        .multilineTextAlignment(.trailing).frame(width: 52)
                }
                .padding(.vertical, 12)
            }
        }
    }

    private var stylesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "Genre & styles")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags.indices, id: \.self) { index in
                        HStack(spacing: 4) {
                            Text(tags[index]).font(.system(size: 14, weight: .semibold))
                            Button { tags.remove(at: index) } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(Palette.badgeAmberText)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Palette.badgeAmberFill, in: Capsule())
                    }
                    Button { showAddStyle = true } label: {
                        Text("+ Add style").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Palette.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var formatSpeed: some View {
        HStack(spacing: 12) {
            menuCard(title: "Format", value: format,
                     options: ["LP", "EP", "7\"", "10\"", "12\"", "2×LP", "Box Set"]) { format = $0 }
            menuCard(title: "Speed", value: "\(speed) RPM",
                     options: ["33⅓ RPM", "45 RPM", "78 RPM"]) { speed = $0.replacingOccurrences(of: " RPM", with: "") }
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "Location")
            GroupedCard(radius: 14, padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
                Menu {
                    Button { locationID = nil } label: {
                        if locationID == nil {
                            Label("None", systemImage: "checkmark")
                        } else {
                            Text("None")
                        }
                    }
                    if !model.locations.isEmpty {
                        Divider()
                        ForEach(model.locations) { location in
                            Button { locationID = location.id } label: {
                                if locationID == location.id {
                                    Label(location.name, systemImage: "checkmark")
                                } else {
                                    Text(location.name)
                                }
                            }
                        }
                    }
                    Divider()
                    Button { newLocationName = ""; showAddLocation = true } label: {
                        Label("New location…", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 15)).foregroundStyle(Palette.tertiary)
                        Text(selectedLocationName)
                            .font(.prBodyEmphasis)
                            .foregroundStyle(locationID == nil ? Palette.secondary : Palette.label)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                    }
                }
            }
        }
    }

    private var selectedLocationName: String {
        model.location(id: locationID)?.name ?? "None"
    }

    private var conditionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "Condition — Goldmine")
            HStack(spacing: 12) {
                conditionCard(title: "Media", selection: $media)
                conditionCard(title: "Sleeve", selection: $sleeve)
            }
        }
    }

    private var ratingCard: some View {
        GroupedCard(radius: 14, padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
            HStack {
                Text("Rating").font(.prBody).foregroundStyle(Palette.label)
                Spacer()
                StarRatingPicker(rating: $rating)
            }
        }
    }

    private var notesCard: some View {
        GroupedCard(radius: 14, padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
            TextField("Notes — pressing details, where you found it…", text: $notes, axis: .vertical)
                .font(.prBody)
                .foregroundStyle(Palette.label)
                .lineLimit(3...6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Row / card helpers

    private func fieldRow(_ label: String, _ text: Binding<String>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(.prBody).foregroundStyle(Palette.secondary)
                    .frame(width: 96, alignment: .leading)
                TextField("", text: text)
                    .font(.prBodyEmphasis).foregroundStyle(Palette.label)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 12)
            HRule()
        }
    }

    private func menuCard(title: String, value: String, options: [String], onPick: @escaping (String) -> Void) -> some View {
        GroupedCard(radius: 14, padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased()).font(.prSmall).foregroundStyle(Palette.tertiary)
                Menu {
                    ForEach(options, id: \.self) { option in
                        Button(option) { onPick(option) }
                    }
                } label: {
                    HStack {
                        Text(value).font(.prBodyEmphasis).foregroundStyle(Palette.label)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func conditionCard(title: String, selection: Binding<Condition?>) -> some View {
        GroupedCard(radius: 14, padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.prSmall).foregroundStyle(Palette.tertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(Condition.allCases, id: \.self) { condition in
                            gradeChip(condition, selected: selection.wrappedValue == condition) {
                                selection.wrappedValue = (selection.wrappedValue == condition) ? nil : condition
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func gradeChip(_ condition: Condition, selected: Bool, action: @escaping () -> Void) -> some View {
        let palette = conditionPalette(condition)
        return Button(action: action) {
            Text(condition.rawValue)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(selected ? palette.text : Palette.tertiary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(selected ? palette.fill : Palette.fill,
                           in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Save

    private func save() {
        let base = mode.initialDetail
        // Reuse the existing/draft id (so a downloaded cover file still matches);
        // a brand-new manual record gets a fresh id.
        let recordID = base?.release.id ?? UUID().uuidString
        let genre = tags.first
        let styles = Array(tags.dropFirst())
        let release = Release(
            id: recordID,
            title: title.trimmingCharacters(in: .whitespaces),
            artistDisplay: artist.trimmingCharacters(in: .whitespaces),
            year: Int(yearText.trimmingCharacters(in: .whitespaces)),
            country: country.isEmpty ? nil : country,
            genre: genre,
            styles: styles,
            format: format,
            speed: speed,
            barcode: base?.release.barcode,
            discogsReleaseID: base?.release.discogsReleaseID,
            musicbrainzMBID: base?.release.musicbrainzMBID,
            coverPath: coverPath,
            thumbPath: thumbPath,
            mediaCondition: media,
            sleeveCondition: sleeve,
            rating: rating,
            notes: notes.isEmpty ? nil : notes,
            addedAt: base?.release.addedAt ?? Date(),
            updatedAt: Date(),
            estimatedValue: base?.release.estimatedValue,
            valueCurrency: base?.release.valueCurrency,
            valueBasis: base?.release.valueBasis,
            valueUpdatedAt: base?.release.valueUpdatedAt,
            locationID: locationID
        )
        let detail = RecordDetail(
            release: release,
            artists: artist.isEmpty ? [] : [Artist(id: UUID().uuidString, name: artist)],
            labels: label.isEmpty ? [] : [LabelCredit(name: label, catalogNumber: catalog.isEmpty ? nil : catalog)],
            tracks: (base?.tracks ?? []).map {
                Track(id: $0.id, releaseID: recordID, position: $0.position, side: $0.side,
                      title: $0.title, durationSeconds: $0.durationSeconds, trackIndex: $0.trackIndex)
            }
        )
        model.save(detail)
        Haptics.success()
        finish()
    }

    private func finish() {
        if let onComplete {
            onComplete()
        } else {
            dismiss()
        }
    }
}
