import SwiftUI
import UniformTypeIdentifiers
import VinylCore

/// First-run setup. Storage is already resolved by the time this appears, so
/// the wizard can *detect* an existing library — on this device or synced from
/// iCloud — rather than asking the user to know where it is.
struct SetupWizardView: View {
    var onFinish: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(LibraryModel.self) private var library
    @State private var token = DiscogsTokenStore.read()
    @AppStorage(SearchMediums.storageKey) private var searchMediumsRaw = MediumFilter.default.storageValue

    @State private var step: Step = .welcome
    @State private var choice: Choice?
    @State private var name = ""
    @State private var tokenDraft = ""
    @State private var useICloud = true

    // Restore
    @State private var showFileImporter = false
    @State private var importPreview: LibraryImporter.Preview?
    @State private var importProgress: Double?
    @State private var importedCount: Int?
    @State private var errorMessage: String?

    enum Step { case welcome, choose, configure, restore, done }

    enum Choice { case existing, fresh, restore }

    /// A library was already found — either left on this device or arriving
    /// from iCloud.
    private var foundExisting: Bool { library.records.count > 0 }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                switch step {
                case .welcome:   welcome
                case .choose:    choose
                case .configure: configure
                case .restore:   restore
                case .done:      done
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.zip, UTType(filenameExtension: "sqlite") ?? .data]
        ) { result in
            handlePickedFile(result)
        }
        .alert("Couldn't read that file", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 8)
            Text("Pacific\nRecord")
                .font(.prDisplay)
                .tracking(-1)
                .foregroundStyle(Palette.label)
                .padding(.bottom, 20)
            Text("Your collection, kept as an open file you own — a plain SQLite database and a folder of covers. No lock-in, ever.")
                .font(.prBody)
                .foregroundStyle(Palette.secondary)
                .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 14) {
                bullet("Scan a barcode to fill in a release")
                bullet("Track Goldmine condition and pressings")
                bullet("Optional Discogs token for richer data")
            }
            Spacer(minLength: 24)
            PrimaryButton(title: "Get started") { advance(to: .choose) }
        }
    }

    // MARK: Choose

    private var choose: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("How would you like to start?")
            Spacer(minLength: 16)

            VStack(spacing: 12) {
                if foundExisting {
                    // Storage resolution already found records — most likely an
                    // iCloud library from another device.
                    option(
                        icon: app.storageMode == .iCloud ? "icloud" : "internaldrive",
                        title: "Use the library that's already here",
                        subtitle: "\(library.records.count) records found\(app.storageMode == .iCloud ? " in iCloud Drive" : " on this iPhone")",
                        highlighted: true
                    ) {
                        choice = .existing
                        advance(to: .done)
                    }
                }
                option(icon: "plus.circle", title: "Start a new library",
                       subtitle: "Name it and add a Discogs token") {
                    choice = .fresh
                    name = library.libraryName ?? ""
                    tokenDraft = token
                    useICloud = app.iCloudAvailable && app.prefersICloud
                    advance(to: .configure)
                }
                option(icon: "square.and.arrow.down", title: "Restore a backup",
                       subtitle: "From a .zip or .sqlite export") {
                    choice = .restore
                    advance(to: .restore)
                }
            }
            Spacer(minLength: 16)
            skipButton
        }
    }

    // MARK: Configure a new library

    private var configure: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Set up your library")
            Spacer(minLength: 16)

            VStack(spacing: 8) {
                fieldCard(label: "Name", placeholder: "My Records", text: $name)
                fieldCard(label: "Discogs", placeholder: "API token (optional)", text: $tokenDraft)
            }
            Text("A Discogs token unlocks richer pressing data and prices. You can add it later in Settings.")
                .font(.prSmall)
                .foregroundStyle(Palette.tertiary)
                .padding(.top, 10)

            mediumChips

            if app.iCloudAvailable {
                GroupedCard() {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Store in iCloud Drive").font(.prBody).foregroundStyle(Palette.label)
                            Text("Synced across devices, visible in Files")
                                .font(.prSmall).foregroundStyle(Palette.tertiary)
                        }
                        Spacer()
                        Toggle("", isOn: $useICloud).labelsHidden().tint(Palette.accent)
                    }
                    .padding(.vertical, 8)
                }
                .padding(.top, 16)
            }

            Spacer(minLength: 24)
            PrimaryButton(title: "Create library") { applyConfiguration() }
            backButton
        }
    }

    // MARK: Restore

    private var restore: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Restore a backup")
            Spacer(minLength: 16)

            if let importProgress {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Restoring…").font(.prBody).foregroundStyle(Palette.label)
                    ProgressView(value: importProgress).tint(Palette.accent)
                }
            } else if let preview = importPreview {
                VStack(alignment: .leading, spacing: 10) {
                    Text(preview.fileName).font(.prBodyEmphasis).foregroundStyle(Palette.label).lineLimit(1)
                    Text(previewSummary(preview))
                        .font(.prSmall).foregroundStyle(Palette.secondary)
                }
                .padding(.bottom, 20)
                PrimaryButton(title: "Restore these records") { runRestore(preview) }
            } else {
                Text("Pick a .zip or .sqlite exported from Pacific Record. Nothing is written until you confirm.")
                    .font(.prBody).foregroundStyle(Palette.secondary)
                    .padding(.bottom, 20)
                PrimaryButton(title: "Choose file") { showFileImporter = true }
            }

            Spacer(minLength: 24)
            if importProgress == nil { backButton }
        }
    }

    private func previewSummary(_ preview: LibraryImporter.Preview) -> String {
        var parts = ["\(preview.recordCount) records"]
        if preview.locationCount > 0 { parts.append("\(preview.locationCount) locations") }
        if preview.coverCount > 0 { parts.append("\(preview.coverCount) covers") }
        return parts.joined(separator: " · ")
    }

    // MARK: Done

    private var done: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 8)
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.accent)
                .padding(.bottom, 20)
            Text(doneTitle)
                .font(.prTitle)
                .foregroundStyle(Palette.label)
                .padding(.bottom, 10)
            Text(doneMessage)
                .font(.prBody)
                .foregroundStyle(Palette.secondary)
            Spacer(minLength: 24)
            PrimaryButton(title: "Open my library", action: onFinish)
        }
    }

    private var doneTitle: String {
        switch choice {
        case .existing: return "Ready to go"
        case .restore:  return "Backup restored"
        default:        return library.libraryName.map { "\($0) is ready" } ?? "Library created"
        }
    }

    private var doneMessage: String {
        switch choice {
        case .existing:
            return "Picking up where you left off — \(library.records.count) records."
        case .restore:
            let count = importedCount ?? library.records.count
            return "\(count) records are back in your library."
        default:
            return token.isEmpty
                ? "Add your first record by scanning a barcode, searching, or entering it by hand."
                : "Discogs is connected. Scan a barcode to add your first record."
        }
    }

    // MARK: Actions

    private func advance(to next: Step) {
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    private func applyConfiguration() {
        library.setLibraryName(name)
        token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        DiscogsTokenStore.write(token)
        if app.iCloudAvailable, useICloud != app.prefersICloud {
            app.setPreferICloud(useICloud)
        }
        Haptics.success()
        advance(to: .done)
    }

    private func handlePickedFile(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            Task {
                do { importPreview = try await LibraryImporter.prepare(from: url) }
                catch { errorMessage = error.localizedDescription }
            }
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }

    private func runRestore(_ preview: LibraryImporter.Preview) {
        importPreview = nil
        importProgress = 0
        Task {
            do {
                // Merge, never replace: a wizard should not be able to destroy
                // anything, even though a fresh install has nothing to lose.
                let summary = try await library.importLibrary(preview, mode: .merge) { fraction in
                    Task { @MainActor in importProgress = fraction }
                }
                importedCount = summary.imported
                Haptics.success()
                advance(to: .done)
            } catch {
                errorMessage = error.localizedDescription
                Haptics.warning()
            }
            LibraryImporter.discard(preview)
            importProgress = nil
        }
    }

    // MARK: Pieces

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.prTitle)
            .foregroundStyle(Palette.label)
            .padding(.top, 8)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Palette.accent).frame(width: 5, height: 5).padding(.top, 8)
            Text(text).font(.prBody).foregroundStyle(Palette.secondary)
        }
    }

    private func option(
        icon: String,
        title: String,
        subtitle: String,
        highlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(highlighted ? Palette.accent : Palette.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.prBodyEmphasis).foregroundStyle(Palette.label)
                    Text(subtitle).font(.prSmall).foregroundStyle(Palette.tertiary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.quaternary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                highlighted ? Palette.accent.opacity(0.12) : Palette.grouped,
                in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    /// The three media almost every collection is made of. The full list — SACD,
    /// reel-to-reel, 8-track — lives in Settings; this is just enough that a CD
    /// collector isn't stuck with vinyl-only searches from day one.
    private var mediumChips: some View {
        let quick: [ReleaseMedium] = [.vinyl, .cd, .cassette]
        let filter = MediumFilter(storageValue: searchMediumsRaw)
        return VStack(alignment: .leading, spacing: 8) {
            Text("I collect")
                .font(.prCaption)
                .tracking(Metrics.overlineTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.tertiary)
            HStack(spacing: 8) {
                ForEach(quick) { medium in
                    let isOn = filter.selected.contains(medium)
                    Button {
                        var selected = filter.selected
                        if selected.contains(medium) { selected.remove(medium) } else { selected.insert(medium) }
                        searchMediumsRaw = MediumFilter(selected: selected).storageValue
                    } label: {
                        Text(medium.displayName)
                            .font(.prFootnote)
                            .foregroundStyle(isOn ? Palette.onPrimary : Palette.secondary)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(isOn ? Palette.accent : Palette.grouped, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(.top, 16)
    }

    private func fieldCard(label: String, placeholder: String, text: Binding<String>) -> some View {
        GroupedCard() {
            HStack {
                Text(label).font(.prBody).foregroundStyle(Palette.secondary)
                    .frame(width: 76, alignment: .leading)
                TextField(placeholder, text: text)
                    .font(.prBodyEmphasis)
                    .foregroundStyle(Palette.label)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(label == "Discogs" ? .never : .words)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 12)
        }
    }

    private var backButton: some View {
        Button { advance(to: .choose) } label: {
            Text("Back")
                .font(.prCaption)
                .tracking(Metrics.overlineTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
        .buttonStyle(.plain)
    }

    private var skipButton: some View {
        Button(action: onFinish) {
            Text("Skip for now")
                .font(.prCaption)
                .tracking(Metrics.overlineTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
        .buttonStyle(.plain)
    }
}
