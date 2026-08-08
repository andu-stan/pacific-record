import SwiftUI
import VisionKit
import VinylCore

// MARK: - Routing

enum AddChoice: Int, Identifiable {
    case scan, search, manual
    var id: Int { rawValue }
}

// MARK: - Chooser sheet

struct AddEntrySheet: View {
    var onSelect: (AddChoice) -> Void
    var onImportCollection: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Palette.quaternary)
                .frame(width: 38, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 0) {
                Text("Add a record")
                    .font(.system(size: 24, weight: .semibold))
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
                    option(icon: "square.and.arrow.down.on.square", iconColor: Palette.positive, title: "Import Discogs collection",
                           subtitle: "Bring in everything from your profile") { onImportCollection() }
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
        .presentationDetents([.height(508)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.grouped)
        .presentationCornerRadius(26)
    }

    private func option(icon: String, iconColor: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 15) {
                ZStack {
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(iconColor)
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
            .background(Palette.fill, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow container

struct AddFlowContainer: View {
    let choice: AddChoice
    @State private var model: AddFlowModel

    init(choice: AddChoice, library: LibraryModel, onFinish: @escaping () -> Void) {
        self.choice = choice
        _model = State(initialValue: AddFlowModel(library: library, onFinish: onFinish))
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            root
                .navigationDestination(for: AddFlowModel.Step.self) { step in
                    switch step {
                    case .matches:
                        MatchView(model: model)
                    case .coverPicker:
                        CoverPickerView(model: model)
                    case .form:
                        RecordFormView(mode: .prefilled(model.formDraft), onComplete: model.onComplete)
                    }
                }
        }
        .tint(Palette.tint)
        .overlay {
            if model.phase == .searching {
                SearchingOverlay(barcode: model.lastBarcode)
            }
        }
        .alert(model.lastSearchWasFilteredOut ? "Nothing on your media" : "No match found", isPresented: emptyAlert) {
            Button("Enter manually") { model.goManual() }
            Button(model.lastBarcode == nil ? "Try again" : "Scan again", role: .cancel) { model.dismissAlert() }
        } message: {
            Text(model.lastSearchWasFilteredOut
                 ? "Releases were found, but none on the media you search for. Change that under Settings › Metadata › Media."
                 : "We couldn't find a release. It may be a promo or a private pressing.")
        }
        .alert("Lookup failed", isPresented: failedAlert) {
            Button("Try again") { model.retry() }
            Button("Enter manually") { model.goManual() }
            Button("Cancel", role: .cancel) { model.finish() }
        } message: {
            Text(failedMessage)
        }
    }

    @ViewBuilder private var root: some View {
        switch choice {
        case .manual: RecordFormView(mode: .new, onComplete: model.onComplete)
        case .scan: ScannerView(model: model)
        case .search: TextSearchView(model: model)
        }
    }

    private var emptyAlert: Binding<Bool> {
        Binding(get: { model.phase == .empty }, set: { if !$0 { model.dismissAlert() } })
    }

    private var failedAlert: Binding<Bool> {
        Binding(get: { if case .failed = model.phase { return true } else { return false } },
                set: { if !$0 { model.dismissAlert() } })
    }

    private var failedMessage: String {
        if case let .failed(message) = model.phase { return message }
        return ""
    }
}

struct SearchingOverlay: View {
    var barcode: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().controlSize(.large).tint(.white)
                Text("Looking up release…").font(.prSection).foregroundStyle(.white)
                if let barcode {
                    Text("Barcode \(barcode)").font(.prSmall).foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(28)
            .background(Palette.overlay, in: RoundedRectangle(cornerRadius: Metrics.overlayRadius, style: .continuous))
        }
    }
}

// MARK: - Scanner

struct ScannerView: View {
    @Bindable var model: AddFlowModel
    @Environment(\.dismiss) private var dismiss
    @State private var torchOn = false
    @State private var typedBarcode = ""

    var body: some View {
        ZStack {
            if DataScannerViewController.isSupported {
                BarcodeScannerView(isTorchOn: torchOn) { model.handleBarcode($0) }
                    .ignoresSafeArea()
                cameraOverlay
            } else {
                unavailable
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var cameraOverlay: some View {
        VStack {
            HStack {
                closeButton
                Spacer()
                Text("Scan barcode").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 34, height: 34)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .stroke(Palette.accent, lineWidth: 3)
                .frame(width: 280, height: 170)
            Text("Line up the barcode on the back cover")
                .font(.prBody).foregroundStyle(.white.opacity(0.85))
                .padding(.top, 20)
            Spacer()

            HStack(spacing: 60) {
                Button { torchOn.toggle() } label: {
                    scannerButton(icon: torchOn ? "bolt.fill" : "bolt.slash.fill", label: "Torch")
                }
                .buttonStyle(.plain)
                Button { model.goManual() } label: {
                    scannerButton(icon: "square.and.pencil", label: "Enter manually")
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 60)
        }
    }

    private var unavailable: some View {
        VStack(spacing: 0) {
            HStack { closeButton; Spacer() }
                .padding(.horizontal, 20).padding(.top, 12)
            Spacer()
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 52)).foregroundStyle(Palette.secondary)
                .padding(.bottom, 20)
            Text("Camera scanning needs a device")
                .font(.prTitle2).foregroundStyle(Palette.label).padding(.bottom, 8)
            Text("The Simulator has no camera. Enter a barcode to test the lookup, or add the record manually.")
                .font(.prBody).foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center).padding(.bottom, 24)
            HStack(spacing: 8) {
                Image(systemName: "barcode").foregroundStyle(Palette.tertiary)
                TextField("Barcode digits", text: $typedBarcode)
                    .keyboardType(.numberPad).font(.prBody).foregroundStyle(Palette.label)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(Palette.controlFill, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .padding(.bottom, 14)
            PrimaryButton(title: "Look up") { model.handleBarcode(typedBarcode) }
                .padding(.bottom, 12)
            SecondaryButton(title: "Enter manually") { model.goManual() }
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }

    private var closeButton: some View {
        let overCamera = DataScannerViewController.isSupported
        return Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(overCamera ? Color.white : Palette.label)
                .frame(width: 34, height: 34)
                .background(overCamera ? Color.black.opacity(0.5) : Palette.grouped, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    private func scannerButton(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22)).foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.15), in: Circle())
            Text(label).font(.prSmall).foregroundStyle(.white)
        }
    }
}

// MARK: - Match / confirm

struct MatchView: View {
    @Bindable var model: AddFlowModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let barcode = model.lastBarcode {
                    barcodeBanner(barcode)
                }
                if let first = model.matches.first {
                    Text("\(first.title.uppercased()) · \(first.artistDisplay.uppercased())")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(Palette.tertiary)
                        .lineLimit(1)
                        .padding(.horizontal, 2)
                        .padding(.bottom, 4)
                }
                ForEach(model.matches) { match in
                    CandidateRow(model: model, match: match)
                }
                Button { model.goManual() } label: {
                    Text("None of these — enter manually")
                        .font(.prHeadline).foregroundStyle(Palette.tint)
                        .frame(maxWidth: .infinity).padding(20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Metrics.screenPadding)
        }
        .background(Palette.background)
        .navigationTitle("Choose pressing")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func barcodeBanner(_ code: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "barcode").font(.system(size: 17)).foregroundStyle(Palette.badgeAmberText)
            VStack(alignment: .leading, spacing: 1) {
                Text(code).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.badgeAmberText)
                Text(bannerSubtitle(code))
                    .font(.prSmall).foregroundStyle(Palette.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Palette.badgeAmberFill, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius).strokeBorder(Palette.accent.opacity(0.3)))
        .padding(.bottom, 14)
    }

    /// Discogs returns loose matches alongside the pressings that really carry
    /// the code, so say how many are exact — that alone often narrows a wall of
    /// look-alike entries to one.
    private func bannerSubtitle(_ code: String) -> String {
        let total = model.matches.count
        let exact = model.matches.filter { $0.carries(barcode: code) }.count
        if exact > 0 && exact < total {
            return "\(total) pressings found · \(exact) carry this exact code"
        }
        return total == 1 ? "1 pressing matches this barcode"
                          : "\(total) pressings match this barcode"
    }
}

/// One candidate pressing. Popular LPs come back from Discogs as a wall of
/// near-identical entries, so the row leads with what actually separates them —
/// the full format descriptors and how many people own this pressing — and can
/// expand to the matrix/runout and pressing plant on request.
struct CandidateRow: View {
    let model: AddFlowModel
    let match: MetadataMatch

    private var detailState: AddFlowModel.DetailState { model.detailState(for: match) }

    private var isExpanded: Bool {
        switch detailState {
        case .unavailable, .collapsed: return false
        case .loading, .loaded, .failed: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button { model.choose(match) } label: { summary }
                .buttonStyle(.plain)

            if detailState != .unavailable {
                Button { model.toggleDetails(for: match) } label: { detailsToggle }
                    .buttonStyle(.plain)
            }

            switch detailState {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading pressing details…").font(.prSmall).foregroundStyle(Palette.tertiary)
                    Spacer()
                }
                .padding(.bottom, 12)
            case let .loaded(detail):
                DetailPanel(match: match, detail: detail)
            case let .failed(message):
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).font(.prSmall).foregroundStyle(Palette.secondary)
                    Button("Try again") { model.retryDetail(for: match) }
                        .font(.prFootnote).foregroundStyle(Palette.tint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            case .unavailable, .collapsed:
                EmptyView()
            }

            HRule()
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            RemoteCoverView(url: match.coverImageURL, seed: match.title)
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(titleLine)
                    .font(.prBodyEmphasis).foregroundStyle(Palette.label).lineLimit(1)
                Text(detailLine)
                    .font(.prSmall).foregroundStyle(Palette.secondary).lineLimit(2)
                if matchesScannedBarcode || (match.community?.have ?? 0) > 0 {
                    HStack(spacing: 6) {
                        if matchesScannedBarcode {
                            RowBadge(text: "Scanned code", fill: Palette.badgeAmberFill, foreground: Palette.badgeAmberText)
                        }
                        if let have = match.community?.have, have > 0 {
                            RowBadge(text: "\(have.formatted()) have",
                                  fill: Palette.badgeNeutralFill, foreground: Palette.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.quaternary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var detailsToggle: some View {
        HStack(spacing: 6) {
            Text(isExpanded ? "Hide pressing details" : "Pressing details")
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
            Spacer()
        }
        .font(.prFootnote)
        .foregroundStyle(Palette.tint)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
    }

    /// Whether this candidate genuinely carries the code that was scanned —
    /// Discogs returns loose matches alongside the exact one.
    private var matchesScannedBarcode: Bool {
        guard let scanned = model.lastBarcode else { return false }
        return match.carries(barcode: scanned)
    }

    private var titleLine: String {
        let label = match.labels.first?.name ?? match.artistDisplay
        if let catalog = match.primaryCatalogNumber { return "\(label) · \(catalog)" }
        return label
    }

    private var detailLine: String {
        [match.year.map(String.init), match.country, match.formatSummary]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// A small capsule of supporting text on a candidate row.
private struct RowBadge: View {
    let text: String
    let fill: Color
    let foreground: Color

    var body: some View {
        Text(text)
            .font(.prBadge)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(fill, in: Capsule())
    }
}

/// The on-demand half: what a single extra Discogs request buys you.
private struct DetailPanel: View {
    let match: MetadataMatch
    let detail: PressingDetail

    /// Matrix and runout etchings first — those are read off the record itself,
    /// so they're what actually settles which pressing you're holding. A
    /// partition rather than a sort, to keep Discogs' order within each half.
    private var identifiers: [ReleaseIdentifier] {
        detail.identifiers.filter(isRunout) + detail.identifiers.filter { !isRunout($0) }
    }

    private func isRunout(_ identifier: ReleaseIdentifier) -> Bool {
        let type = identifier.type.lowercased()
        return type.contains("matrix") || type.contains("runout")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if detail.isEmpty {
                Text("Discogs has no extra pressing detail for this entry.")
                    .font(.prSmall).foregroundStyle(Palette.tertiary)
            }
            if let released = detail.released {
                field("Released", values: [released])
            }
            ForEach(groupedIdentifiers) { group in
                field(group.type, values: group.values)
            }
            if !detail.credits.isEmpty {
                field("Credits", values: detail.credits.prefix(4).map { "\($0.role) — \($0.name)" })
            }
            if let notes = detail.notes {
                field("Notes", values: [notes], lineLimit: 4)
            }
            if detail.numForSale > 0 {
                Text(marketLine)
                    .font(.prSmall).foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 14) {
                if let url = match.webURL {
                    Link("View on Discogs", destination: url)
                }
                if let url = match.allVersionsURL {
                    Link("All versions", destination: url)
                }
            }
            .font(.prFootnote)
            .foregroundStyle(Palette.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .padding(.bottom, 12)
    }

    /// One block per identifier type, so four runout etchings don't repeat the
    /// heading four times. Capped — some releases list dozens.
    private var groupedIdentifiers: [IdentifierGroup] {
        var order: [String] = []
        var byType: [String: [String]] = [:]
        for identifier in identifiers.prefix(12) {
            if byType[identifier.type] == nil { order.append(identifier.type) }
            let note = identifier.note.map { " (\($0))" } ?? ""
            byType[identifier.type, default: []].append(identifier.value + note)
        }
        return order.prefix(4).map { IdentifierGroup(type: $0, values: byType[$0] ?? []) }
    }

    private var marketLine: String {
        let copies = detail.numForSale == 1 ? "1 copy for sale" : "\(detail.numForSale.formatted()) copies for sale"
        guard let price = detail.lowestPrice else { return copies }
        return "\(copies) from \(price.amount.formatted(.currency(code: price.currency)))"
    }

    private func field(_ label: String, values: [String], lineLimit: Int = 2) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.prBadge)
                .tracking(Metrics.overlineTracking)
                .foregroundStyle(Palette.tertiary)
            ForEach(values.indices, id: \.self) { index in
                Text(values[index])
                    .font(.prSmall)
                    .foregroundStyle(Palette.label)
                    .lineLimit(lineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Identifiers of one kind ("Matrix / Runout") gathered under a single heading.
private struct IdentifierGroup: Identifiable {
    let type: String
    let values: [String]

    var id: String { type }
}

// MARK: - Cover picker

struct CoverPickerView: View {
    @Bindable var model: AddFlowModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pick the cover to use for this record.")
                    .font(.prBody).foregroundStyle(Palette.secondary)

                CoverChooserGrid(candidates: model.coverCandidates, seed: model.pickerSeed) { model.selectCover($0) }

                Button { model.selectCover(nil) } label: {
                    Text("Skip — add without a cover")
                        .font(.prHeadline).foregroundStyle(Palette.tint)
                        .frame(maxWidth: .infinity).padding(.top, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Palette.background)
        .navigationTitle("Choose cover")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Text search

struct TextSearchView: View {
    @Bindable var model: AddFlowModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.tertiary)
                    TextField("Artist or album title", text: $query)
                        .font(.prBody).foregroundStyle(Palette.label)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { model.runTextSearch(query) }
                    if !query.isEmpty {
                        Button("Search") { model.runTextSearch(query) }
                            .font(.prFootnote).foregroundStyle(Palette.tint)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Palette.controlFill, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                .padding(.bottom, 14)

                if model.matches.isEmpty {
                    Text("Search by artist or album title, then pick the exact pressing.")
                        .font(.prBody).foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    ForEach(model.matches) { match in
                        CandidateRow(model: model, match: match)
                    }
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
        }
        .background(Palette.background)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
        }
    }
}
