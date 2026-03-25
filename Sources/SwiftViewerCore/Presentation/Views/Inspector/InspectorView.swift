import CoreData
import SwiftUI

private struct PendingLensBatchApply {
    let items: [FileItem]
    let field: MainViewModel.LensMetadataField
}

struct InspectorView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var pendingLensBatch: PendingLensBatchApply?

    init(viewModel: MainViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inspector")
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView(.vertical) {
                let selection = Array(viewModel.selectedFiles)
                if selection.count > 1 {
                    multiSelectionView(selection: selection)
                } else if let item = viewModel.currentFile ?? selection.first,
                    let exif = viewModel.metadataCache[item.url.standardizedFileURL]
                {
                    singleSelectionView(item: item, exif: exif)
                        .id(item.id)
                } else {
                    Text("No selection or no metadata")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
        .frame(minWidth: 200, idealWidth: 250, maxWidth: 400)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .leading
        )
        .confirmationDialog(
            "レンズ情報の一括更新",
            isPresented: Binding(
                get: { pendingLensBatch != nil },
                set: { if !$0 { pendingLensBatch = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingLensBatch
        ) { pending in
            Button("適用") {
                viewModel.applyLensMetadata(for: pending.items, field: pending.field)
                pendingLensBatch = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("キャンセル", role: .cancel) {
                pendingLensBatch = nil
            }
        } message: { pending in
            Text(
                "選択中の \(pending.items.count) 件にレンズ情報を反映します。RAW はファイルへ書き込みません（カタログに登録がある場合はカタログのみ更新）。JPEG 等は ExifTool で埋め込みます。"
            )
        }
    }

    private var editableSelection: [FileItem] {
        let selection = Array(viewModel.selectedFiles)
        // Always filter out RAW files for metadata display/editing logic
        return selection.filter { !isRAW($0) }
    }



    private var commonRating: Int {
        let selection = editableSelection
        guard !selection.isEmpty else { return 0 }

        let firstRating = viewModel.metadataCache[selection.first!.url.standardizedFileURL]?.rating ?? selection.first?.rating ?? 0
        let allSame = selection.allSatisfy {
            (viewModel.metadataCache[$0.url.standardizedFileURL]?.rating ?? $0.rating ?? 0) == firstRating
        }
        return allSame ? Int(firstRating) : 0
    }

    private var commonLabel: String? {
        let selection = editableSelection
        guard !selection.isEmpty else { return nil }

        // Use metadata cache if available
        let firstLabel =
            viewModel.metadataCache[selection.first!.url.standardizedFileURL]?.colorLabel ?? selection.first?.colorLabel
        let allSame = selection.allSatisfy { item in
            let label = viewModel.metadataCache[item.url.standardizedFileURL]?.colorLabel ?? item.colorLabel
            return label == firstLabel
        }
        return allSame ? firstLabel : nil
    }

    private var commonFavorite: Bool? {
        let selection = editableSelection
        guard !selection.isEmpty else { return nil }

        // Use metadata cache if available
        let firstFav =
            viewModel.metadataCache[selection.first!.url.standardizedFileURL]?.isFavorite ?? selection.first?.isFavorite
        let allSame = selection.allSatisfy { item in
            let fav = viewModel.metadataCache[item.url.standardizedFileURL]?.isFavorite ?? item.isFavorite
            return fav == firstFav
        }
        return allSame ? firstFav : nil
    }

    private var commonFlag: Int? {
        let selection = editableSelection
        guard !selection.isEmpty else { return nil }

        // Use metadata cache if available
        let firstFlag =
            viewModel.metadataCache[selection.first!.url.standardizedFileURL]?.flagStatus
            ?? Int(selection.first?.flagStatus ?? 0)
        let allSame = selection.allSatisfy { item in
            let flag = viewModel.metadataCache[item.url.standardizedFileURL]?.flagStatus ?? Int(item.flagStatus ?? 0)
            return flag == firstFlag
        }
        return allSame ? firstFlag : nil
    }

    private func multiSelectionView(selection: [FileItem]) -> some View {
        // Check if at least one item is editable
        let anyEditable = selection.contains { !isRAW($0) }

        return VStack(alignment: .leading, spacing: 16) {
            Text("Multiple items selected")
                .font(.headline)
            Text("\(selection.count) items")
                .foregroundStyle(.secondary)

            Divider()

            // Editable Metadata (Batch)
            Text("Metadata (Batch)").font(.subheadline).bold()

            // Rating
            HStack {
                Text("Rating")
                Spacer()
                RatingView(rating: commonRating) { newRating in
                    viewModel.updateRating(for: selection, rating: newRating)
                }
                .opacity(anyEditable ? 1.0 : 0.5)
                .disabled(!anyEditable)
            }

            // Favorite (Available in both modes, read-only for RAW in Folders)
            // if viewModel.appMode == .catalog { // Removed to allow RGB editing in Folders
            if true {
                HStack {
                    Text("Favorite")
                    Spacer()
                    Button(action: {
                        viewModel.toggleFavorite(for: selection)
                    }) {
                        Image(systemName: commonFavorite == true ? "heart.fill" : "heart")
                            .foregroundStyle(commonFavorite == true ? .pink : .gray)
                    }
                    .buttonStyle(.plain)
                }

                // Flag
                HStack {
                    Text("Flag")
                    Spacer()
                    HStack(spacing: 8) {
                        Button(action: {
                            viewModel.setFlagStatus(for: selection, status: 1)
                        }) {
                            Image(systemName: "flag.fill")
                                .foregroundStyle(commonFlag == 1 ? Color.green : Color.gray)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            viewModel.setFlagStatus(for: selection, status: -1)
                        }) {
                            Image(systemName: "flag.slash.fill")
                                .foregroundStyle(commonFlag == -1 ? Color.red : Color.gray)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            viewModel.setFlagStatus(for: selection, status: 0)
                        }) {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(
                                    commonFlag == 0 ? Color(nsColor: .labelColor) : Color.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Color Label
            HStack {
                Text("Label")
                Spacer()
                ColorLabelPicker(selection: commonLabel) { newLabel in
                    viewModel.updateColorLabel(for: selection, label: newLabel)
                }
                .opacity(anyEditable ? 1.0 : 0.5)
                .disabled(!anyEditable)
            }

            Divider()

            MultiLensBatchSection(
                selection: selection,
                viewModel: viewModel,
                isEditableItem: { isEditable($0) },
                pendingLensBatch: $pendingLensBatch
            )

            if !anyEditable {
                Text("Editing disabled for RAW files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func isEditable(_ item: FileItem) -> Bool {
        if isRAW(item) {
            // RAW files are editable ONLY in Catalog mode AND NOT in Photos mode
            return viewModel.appMode == .catalog && viewModel.selectedPhotosGroupID == nil
        }
        return true
    }

    private func singleSelectionView(item: FileItem, exif: ExifMetadata) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Basic Info
            Group {
                Text("General").font(.subheadline).bold()
                HStack {
                    Text("Filename")
                    Spacer()
                    Text(item.name)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Dimensions")
                    Spacer()
                    Text("\(exif.width ?? 0) x \(exif.height ?? 0)")
                        .foregroundStyle(.secondary)
                }
                if let date = exif.dateTimeOriginal {
                    HStack {
                        Text("Date")
                        Spacer()
                        Text(date.formatted())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // Camera Info
            Group {
                Text("Camera").font(.subheadline).bold()
                HStack {
                    Text("Make")
                    Spacer()
                    Text(exif.cameraMake ?? "-")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Model")
                    Spacer()
                    Text(exif.cameraModel ?? "-")
                        .foregroundStyle(.secondary)
                }
                SingleLensMetadataEditor(
                    viewModel: viewModel,
                    item: item,
                    exif: exif,
                    enabled: isEditable(item),
                    isRAW: isRAW(item)
                )
                HStack {
                    Text("Software")
                    Spacer()
                    Text(exif.software ?? "-")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Serial")
                    Spacer()
                    Text(exif.serialNumber ?? "-")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Shooting Info
            Group {
                Text("Shooting").font(.subheadline).bold()
                HStack {
                    Text("Focal Length")
                    Spacer()
                    Text(String(format: "%.0f mm", exif.focalLength ?? 0))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Aperture")
                    Spacer()
                    Text(String(format: "f/%.1f", exif.aperture ?? 0))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Shutter")
                    Spacer()
                    Text(exif.shutterSpeed ?? "-")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("ISO")
                    Spacer()
                    Text("\(exif.iso ?? 0)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Exposure Comp.")
                    Spacer()
                    Text(String(format: "%.1f EV", exif.exposureCompensation ?? 0.0))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Metering")
                    Spacer()
                    Text(exif.meteringMode ?? "-")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Flash")
                    Spacer()
                    Text(exif.flash ?? "-")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("White Balance")
                    Spacer()
                    Text(exif.whiteBalance ?? "-")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Program")
                    Spacer()
                    Text(exif.exposureProgram ?? "-")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Brightness")
                    Spacer()
                    Text(String(format: "%.2f", exif.brightnessValue ?? 0.0))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Exp. Bias")
                    Spacer()
                    Text(String(format: "%.2f EV", exif.exposureBias ?? 0.0))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Description Info
            Group {
                Text("Description").font(.subheadline).bold()
                HStack {
                    Text("Title")
                    Spacer()
                    Text(exif.title ?? "-")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(alignment: .top) {
                    Text("Caption")
                    Spacer()
                    Text(exif.caption ?? "-")
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.trailing)
                }
            }

            Divider()

            // Location Info
            Group {
                Text("Location").font(.subheadline).bold()
                HStack {
                    Text("Latitude")
                    Spacer()
                    Text(String(format: "%.6f", exif.latitude ?? 0.0))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Longitude")
                    Spacer()
                    Text(String(format: "%.6f", exif.longitude ?? 0.0))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Altitude")
                    Spacer()
                    Text(String(format: "%.1f m", exif.altitude ?? 0.0))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Direction")
                    Spacer()
                    Text(String(format: "%.1f°", exif.imageDirection ?? 0.0))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Editable Metadata
            Group {
                Text("Metadata").font(.subheadline).bold()

                // Rating
                HStack {
                    Text("Rating")
                    Spacer()
                    RatingView(rating: Int(exif.rating ?? 0)) { newRating in
                        viewModel.updateRating(for: item, rating: newRating)
                    }
                    .opacity(isEditable(item) ? 1.0 : 0.5)
                    .disabled(!isEditable(item))
                }

                // Favorite
                HStack {
                    Text("Favorite")
                    Spacer()
                    Button(action: {
                        viewModel.toggleFavorite(for: [item])
                    }) {
                        let isFav = viewModel.metadataCache[item.url.standardizedFileURL]?.isFavorite ?? item.isFavorite
                        Image(systemName: isFav == true ? "heart.fill" : "heart")
                            .foregroundStyle(isFav == true ? .pink : .gray)
                    }
                    .buttonStyle(.plain)
                }
                .opacity(isEditable(item) ? 1.0 : 0.5)
                .disabled(!isEditable(item))

                // Flag
                HStack {
                    Text("Flag")
                    Spacer()
                    HStack(spacing: 8) {
                        let flagStatus =
                            viewModel.metadataCache[item.url.standardizedFileURL]?.flagStatus
                            ?? Int(item.flagStatus ?? 0)

                        Button(action: {
                            viewModel.setFlagStatus(for: [item], status: 1)
                        }) {
                            Image(systemName: "flag.fill")
                            .foregroundStyle(flagStatus == 1 ? Color.green : Color.gray)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            viewModel.setFlagStatus(for: [item], status: -1)
                        }) {
                            Image(systemName: "flag.slash.fill")
                            .foregroundStyle(flagStatus == -1 ? Color.red : Color.gray)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            viewModel.setFlagStatus(for: [item], status: 0)
                        }) {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(
                                    flagStatus == 0 ? Color(nsColor: .labelColor) : Color.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .opacity(isEditable(item) ? 1.0 : 0.5)
                .disabled(!isEditable(item))

                // Color Label
                HStack {
                    Text("Label")
                    Spacer()
                    ColorLabelPicker(selection: viewModel.metadataCache[item.url.standardizedFileURL]?.colorLabel ?? item.colorLabel) { newLabel in
                        viewModel.updateColorLabel(for: [item], label: newLabel)
                    }
                    .opacity(isEditable(item) ? 1.0 : 0.5)
                    .disabled(!isEditable(item))
                }
                
                if !isEditable(item) {
                    Text("Editing disabled for RAW files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Debug Info
                Divider()
                Group {
                    Text("Debug Info").font(.caption).bold()
                    Text("Ext: \(item.url.pathExtension)")
                    Text(
                        "Is RAW: \(FileConstants.rawExtensions.contains(item.url.pathExtension.lowercased()) ? "Yes" : "No")"
                    )
                    Text(
                        "Is Catalog: \(viewModel.appMode == .catalog || viewModel.currentCatalog != nil ? "Yes" : "No")"
                    )
                    Text("Disabled: \(isRAW(item) && viewModel.appMode != .catalog ? "Yes" : "No")")
                    Text("ExifTool: \(viewModel.isExifToolAvailable ? "Available" : "Not Found")")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func isRAW(_ item: FileItem) -> Bool {
        let urlExt = item.url.standardizedFileURL.pathExtension.lowercased()
        if !urlExt.isEmpty {
            return FileConstants.rawExtensions.contains(urlExt)
        }
        // Fallback to name if URL has no extension (e.g. Photos asset)
        let nameExt = (item.name as NSString).pathExtension.lowercased()
        return FileConstants.rawExtensions.contains(nameExt)
    }
}

// MARK: - Lens metadata editing

private struct SingleLensMetadataEditor: View {
    @ObservedObject var viewModel: MainViewModel
    let item: FileItem
    let exif: ExifMetadata
    let enabled: Bool
    let isRAW: Bool
    @State private var draftMake: String = ""
    @State private var draftModel: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Lens make")
                    .frame(minWidth: 76, alignment: .leading)
                TextField("", text: $draftMake)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!enabled)
                Button("適用") {
                    viewModel.applyLensMetadata(for: [item], field: .lensMake(draftMake))
                }
                .disabled(!enabled)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Lens name")
                    .frame(minWidth: 76, alignment: .leading)
                TextField("", text: $draftModel)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!enabled)
                Button("適用") {
                    viewModel.applyLensMetadata(for: [item], field: .lensModel(draftModel))
                }
                .disabled(!enabled)
            }
            if !viewModel.isExifToolAvailable, enabled, !isRAW {
                Text("ExifTool が見つかりません。埋め込みへの書き込みはスキップされます。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            sync(from: exif)
        }
        .onChange(of: item.id) { _, _ in
            sync(from: exif)
        }
    }

    private func sync(from exif: ExifMetadata) {
        draftMake = exif.lensMake ?? ""
        draftModel = exif.lensModel ?? ""
    }
}

private struct MultiLensBatchSection: View {
    let selection: [FileItem]
    @ObservedObject var viewModel: MainViewModel
    let isEditableItem: (FileItem) -> Bool
    @Binding var pendingLensBatch: PendingLensBatchApply?
    @State private var draftMake: String = ""
    @State private var draftModel: String = ""

    private var anyLensEditable: Bool {
        selection.contains(where: isEditableItem)
    }

    private var selectionSignature: String {
        selection.map(\.id).sorted().joined(separator: ",")
    }

    /// Includes cached lens strings so drafts refresh after a batch apply.
    private var lensSnapshot: String {
        selection
            .map { item in
                let m = cached(item)
                return "\(item.id)|\(m?.lensMake ?? "\u{FFFC}")|\(m?.lensModel ?? "\u{FFFC}")"
            }
            .joined(separator: ";")
    }

    private func cached(_ item: FileItem) -> ExifMetadata? {
        viewModel.metadataCache[item.url.standardizedFileURL]
    }

    private var lensMakeIsUniform: Bool {
        guard let first = selection.first else { return true }
        let ref = cached(first)?.lensMake
        return selection.allSatisfy { cached($0)?.lensMake == ref }
    }

    private var lensModelIsUniform: Bool {
        guard let first = selection.first else { return true }
        let ref = cached(first)?.lensModel
        return selection.allSatisfy { cached($0)?.lensModel == ref }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lens (batch)").font(.subheadline).bold()

            HStack(alignment: .firstTextBaseline) {
                Text("Lens make")
                    .frame(minWidth: 76, alignment: .leading)
                TextField("", text: $draftMake)
                    .textFieldStyle(.roundedBorder)
                Button("適用") {
                    pendingLensBatch = PendingLensBatchApply(
                        items: selection,
                        field: .lensMake(draftMake)
                    )
                }
                .disabled(!anyLensEditable)
            }
            if !lensMakeIsUniform {
                Text("（値が複数あります）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Lens name")
                    .frame(minWidth: 76, alignment: .leading)
                TextField("", text: $draftModel)
                    .textFieldStyle(.roundedBorder)
                Button("適用") {
                    pendingLensBatch = PendingLensBatchApply(
                        items: selection,
                        field: .lensModel(draftModel)
                    )
                }
                .disabled(!anyLensEditable)
            }
            if !lensModelIsUniform {
                Text("（値が複数あります）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.isExifToolAvailable, anyLensEditable {
                Text("ExifTool がない場合、JPEG 等への埋め込みは行われません。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !anyLensEditable {
                Text("フォルダモードの RAW のみが選ばれているため、レンズ情報は更新できません。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(anyLensEditable ? 1.0 : 0.55)
        .onAppear {
            syncDrafts()
        }
        .onChange(of: selectionSignature) { _, _ in
            syncDrafts()
        }
        .onChange(of: lensSnapshot) { _, _ in
            syncDrafts()
        }
    }

    private func syncDrafts() {
        guard let first = selection.first else {
            draftMake = ""
            draftModel = ""
            return
        }
        if lensMakeIsUniform {
            draftMake = cached(first)?.lensMake ?? ""
        } else {
            draftMake = ""
        }
        if lensModelIsUniform {
            draftModel = cached(first)?.lensModel ?? ""
        } else {
            draftModel = ""
        }
    }
}

struct RatingView: View {
    let rating: Int
    let onTap: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= rating ? "star.fill" : "star")
                    .foregroundStyle(index <= rating ? .yellow : .gray)
                    .onTapGesture {
                        onTap(index == rating ? 0 : index)  // Toggle off if same
                    }
            }
        }
    }
}

struct ColorLabelPicker: View {
    let selection: String?
    let onTap: (String?) -> Void

    let colors = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"]

    var body: some View {
        HStack(spacing: 4) {
            // None
            Image(systemName: "circle.slash")
                .font(.system(size: 16))
                .foregroundColor(selection == nil ? .primary : .secondary)
                .onTapGesture {
                    Logger.shared.log("InspectorView: ColorLabelPicker cleared.")
                    onTap(nil)
                }

            ForEach(colors, id: \.self) { colorName in
                Circle()
                    .fill(colorFromString(colorName))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(Color.primary, lineWidth: selection == colorName ? 2 : 0)
                    )
                    .onTapGesture {
                        let newLabel = selection == colorName ? nil : colorName
                        Logger.shared.log(
                            "InspectorView: ColorLabelPicker tapped \(colorName). New label: \(newLabel ?? "nil")"
                        )
                        onTap(newLabel)
                    }
            }
        }
    }

    private func colorFromString(_ name: String) -> Color {
        switch name {
        case "Red": return .red
        case "Orange": return .orange
        case "Yellow": return .yellow
        case "Green": return .green
        case "Blue": return .blue
        case "Purple": return .purple
        case "Gray": return .gray
        default: return .clear
        }
    }
}
