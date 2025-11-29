import SwiftUI
import CoreData

struct InspectorView: View {
    @ObservedObject var viewModel: MainViewModel
    
    @State private var batchRating: Int = 0
    @State private var batchLabel: String? = nil
    
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
                    // Multiple Selection Mode
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Multiple items selected")
                            .font(.headline)
                        Text("\(selection.count) items")
                            .foregroundStyle(.secondary)
                        
                        Divider()
                        
                        // Editable Metadata (Batch)
                        Group {
                            Text("Metadata (Batch)").font(.subheadline).bold()
                            
                            // Check if at least one item is editable
                            let anyEditable = selection.contains { !isRAW($0) }
                            
                            // Rating
                            HStack {
                                Text("Rating")
                                Spacer()
                                RatingView(rating: batchRating) { newRating in
                                    batchRating = newRating
                                    viewModel.updateRating(for: selection, rating: newRating)
                                }
                                .opacity(anyEditable ? 1.0 : 0.5)
                                .disabled(!anyEditable)
                            }
                            
                            // Color Label
                            HStack {
                                Text("Label")
                                Spacer()
                                ColorLabelPicker(selection: batchLabel) { newLabel in
                                    batchLabel = newLabel
                                    viewModel.updateColorLabel(for: selection, label: newLabel)
                                }
                                .opacity(anyEditable ? 1.0 : 0.5)
                                .disabled(!anyEditable)
                            }
                            
                            if !anyEditable {
                                Text("Editing disabled for RAW files.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .onChange(of: selection.map(\.id)) { _ in
                        // Reset batch state when SELECTION changes (not when metadata updates)
                        batchRating = 0
                        batchLabel = nil
                    }
                    
                } else if let item = viewModel.currentFile ?? selection.first, let exif = viewModel.metadataCache[item.url] {
                    // Single Item Mode
                    VStack(alignment: .leading, spacing: 16) {
                        // Basic Info
                        Group {
                            Text("General").font(.subheadline).bold()
                            LabeledContent("Filename", value: item.name)
                            LabeledContent("Dimensions", value: "\(exif.width ?? 0) x \(exif.height ?? 0)")
                            if let date = exif.dateTimeOriginal {
                                LabeledContent("Date", value: date.formatted())
                            }
                        }
                        
                        Divider()
                        
                        // Camera Info
                        Group {
                            Text("Camera").font(.subheadline).bold()
                            LabeledContent("Make", value: exif.cameraMake ?? "-")
                            LabeledContent("Model", value: exif.cameraModel ?? "-")
                            LabeledContent("Lens", value: exif.lensModel ?? "-")
                            LabeledContent("Software", value: exif.software ?? "-")
                        }
                        
                        Divider()
                        
                        // Shooting Info
                        Group {
                            Text("Shooting").font(.subheadline).bold()
                            LabeledContent("Focal Length", value: String(format: "%.0f mm", exif.focalLength ?? 0))
                            LabeledContent("Aperture", value: String(format: "f/%.1f", exif.aperture ?? 0))
                            LabeledContent("Shutter", value: exif.shutterSpeed ?? "-")
                            LabeledContent("ISO", value: "\(exif.iso ?? 0)")
                            LabeledContent("Exposure Comp.", value: String(format: "%.1f EV", exif.exposureCompensation ?? 0.0))
                            LabeledContent("Metering", value: exif.meteringMode ?? "-")
                            LabeledContent("Flash", value: exif.flash ?? "-")
                            LabeledContent("White Balance", value: exif.whiteBalance ?? "-")
                            LabeledContent("Program", value: exif.exposureProgram ?? "-")
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
                                // Enable if NOT RAW OR (Is RAW AND In Catalog)
                                .opacity((!isRAW(item) || viewModel.appMode == .catalog) ? 1.0 : 0.5)
                                .disabled(isRAW(item) && viewModel.appMode != .catalog)
                            }
                            
                            // Color Label
                            HStack {
                                Text("Label")
                                Spacer()
                                ColorLabelPicker(selection: item.colorLabel) { newLabel in
                                    viewModel.updateColorLabel(for: item, label: newLabel)
                                }
                                // Enable if NOT RAW OR (Is RAW AND In Catalog)
                                .opacity((!isRAW(item) || viewModel.appMode == .catalog) ? 1.0 : 0.5)
                                .disabled(isRAW(item) && viewModel.appMode != .catalog)
                            }
                            
                            // Debug Info
                            Divider()
                            Group {
                                Text("Debug Info").font(.caption).bold()
                                Text("Ext: \(item.url.pathExtension)")
                                Text("Is RAW: \(FileConstants.rawExtensions.contains(item.url.pathExtension.lowercased()) ? "Yes" : "No")")
                                Text("Is Catalog: \(viewModel.appMode == .catalog || viewModel.currentCatalog != nil ? "Yes" : "No")")
                                Text("Disabled: \(isRAW(item) && viewModel.appMode != .catalog ? "Yes" : "No")")
                                Text("ExifTool: \(viewModel.isExifToolAvailable ? "Available" : "Not Found")")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
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
    }
    
    private func isRAW(_ item: FileItem) -> Bool {
        return FileConstants.rawExtensions.contains(item.url.pathExtension.lowercased())
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
                        onTap(index == rating ? 0 : index) // Toggle off if same
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
                        Logger.shared.log("InspectorView: ColorLabelPicker tapped \(colorName). New label: \(newLabel ?? "nil")")
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
