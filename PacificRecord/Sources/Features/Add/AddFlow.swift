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
        .alert("No match found", isPresented: emptyAlert) {
            Button("Enter manually") { model.goManual() }
            Button(model.lastBarcode == nil ? "Try again" : "Scan again", role: .cancel) { model.dismissAlert() }
        } message: {
            Text("We couldn't find a release. It may be a promo or a private pressing.")
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
            .background(Color(hex: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
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
            .background(Palette.controlFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
                .font(.system(size: 15, weight: .bold))
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
                    Button { model.choose(match) } label: { CandidateRow(match: match) }
                        .buttonStyle(.plain)
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
                Text(model.matches.count == 1 ? "1 pressing matches this barcode"
                                              : "\(model.matches.count) pressings match this barcode")
                    .font(.prSmall).foregroundStyle(Palette.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Palette.badgeAmberFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.accent.opacity(0.3)))
        .padding(.bottom, 14)
    }
}

struct CandidateRow: View {
    let match: MetadataMatch

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                RemoteCoverView(url: match.coverImageURL, seed: match.title)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleLine)
                        .font(.prBodyEmphasis).foregroundStyle(Palette.label).lineLimit(1)
                    Text(detailLine)
                        .font(.prSmall).foregroundStyle(Palette.secondary).lineLimit(1)
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

    private var titleLine: String {
        let label = match.labels.first?.name ?? match.artistDisplay
        if let catalog = match.primaryCatalogNumber { return "\(label) · \(catalog)" }
        return label
    }

    private var detailLine: String {
        [match.year.map(String.init), match.country, match.format]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
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
                .background(Palette.controlFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .padding(.bottom, 14)

                if model.matches.isEmpty {
                    Text("Search by artist or album title, then pick the exact pressing.")
                        .font(.prBody).foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    ForEach(model.matches) { match in
                        Button { model.choose(match) } label: { CandidateRow(match: match) }
                            .buttonStyle(.plain)
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
