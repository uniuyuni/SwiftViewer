import SwiftUI

struct FilterBarView: View {
    @ObservedObject var viewModel: MainViewModel
    // @State private var selectedTab: Int = 0 // Removed
    
    var body: some View {
        VStack(spacing: 0) {
            // Tabs
            HStack {
                Button("Text") { viewModel.filterTabSelection = 0 }
                    .buttonStyle(FilterTabButtonStyle(isSelected: viewModel.filterTabSelection == 0))
                Button("Attribute") { viewModel.filterTabSelection = 1 }
                    .buttonStyle(FilterTabButtonStyle(isSelected: viewModel.filterTabSelection == 1))
                Button("Metadata") { viewModel.filterTabSelection = 2 }
                    .buttonStyle(FilterTabButtonStyle(isSelected: viewModel.filterTabSelection == 2))
                
                Spacer()
                
                Toggle("Active", isOn: Binding(
                    get: { !viewModel.isFilterDisabled },
                    set: { viewModel.isFilterDisabled = !$0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            if !viewModel.isFilterDisabled {
                Group {
                    if viewModel.filterTabSelection == 0 {
                        TextFilterView(viewModel: viewModel)
                    } else if viewModel.filterTabSelection == 1 {
                        AttributeFilterView(viewModel: viewModel)
                    } else {
                        MetadataFilterView(viewModel: viewModel)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
    }
}

struct FilterTabButtonStyle: ButtonStyle {
    var isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(4)
    }
}

struct TextFilterView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Search...", text: $viewModel.filterCriteria.searchText)
                .textFieldStyle(.roundedBorder)
            if !viewModel.filterCriteria.searchText.isEmpty {
                Button(action: { viewModel.filterCriteria.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AttributeFilterView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {

        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Rating & Label
            HStack(spacing: 16) {
                // Rating
                HStack(spacing: 2) {
                    Text("Rating")
                        .foregroundStyle(.secondary)
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: viewModel.filterCriteria.minRating >= star ? "star.fill" : "star")
                            .foregroundStyle(.orange)
                            .onTapGesture {
                                viewModel.filterCriteria.minRating = (viewModel.filterCriteria.minRating == star) ? 0 : star
                                viewModel.applyFilter()
                            }
                    }
                }
                
                Divider()
                    .frame(height: 16)
                
                // Label
                HStack(spacing: 4) {
                    Text("Label")
                        .foregroundStyle(.secondary)
                    ForEach(["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"], id: \.self) { color in
                        Circle()
                            .fill(colorFromString(color))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary, lineWidth: viewModel.filterCriteria.colorLabel == color ? 1 : 0)
                            )
                            .onTapGesture {
                                if viewModel.filterCriteria.colorLabel == color {
                                    viewModel.filterCriteria.colorLabel = nil
                                } else {
                                    viewModel.filterCriteria.colorLabel = color
                                }
                                viewModel.applyFilter()
                            }
                    }
                }
                
                Spacer()
            }
            
            // Row 2: Favorites, Flags, Media Type
            HStack(spacing: 16) {
                // Favorites
                Toggle(isOn: Binding(
                    get: { viewModel.filterCriteria.showOnlyFavorites },
                    set: {
                        viewModel.filterCriteria.showOnlyFavorites = $0
                        viewModel.applyFilter()
                    }
                )) {
                    Image(systemName: viewModel.filterCriteria.showOnlyFavorites ? "heart.fill" : "heart")
                        .foregroundStyle(viewModel.filterCriteria.showOnlyFavorites ? .pink : .secondary)
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .help("Show Only Favorites")
                
                Divider()
                    .frame(height: 16)
                
                // Flags
                Picker("Flag", selection: Binding(
                    get: { viewModel.filterCriteria.flagFilter },
                    set: {
                        viewModel.filterCriteria.flagFilter = $0
                        viewModel.applyFilter()
                    }
                )) {
                    ForEach(FilterCriteria.FlagFilter.allCases, id: \.self) { flag in
                        Text(flag.rawValue).tag(flag)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                
                Divider()
                    .frame(height: 16)
                
                // Media Type
                HStack(spacing: 0) {
                    Toggle(isOn: Binding(
                        get: { viewModel.filterCriteria.showImages },
                        set: {
                            viewModel.filterCriteria.showImages = $0
                            viewModel.applyFilter()
                        }
                    )) {
                        Image(systemName: "photo")
                    }
                    .toggleStyle(.button)
                    .help("Show Images")
                    
                    Toggle(isOn: Binding(
                        get: { viewModel.filterCriteria.showVideos },
                        set: {
                            viewModel.filterCriteria.showVideos = $0
                            viewModel.applyFilter()
                        }
                    )) {
                        Image(systemName: "video")
                    }
                    .toggleStyle(.button)
                    .help("Show Videos")
                }
                
                Spacer()
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        default: return .gray
        }
    }
}

struct MetadataFilterView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        if viewModel.isLoadingMetadata {
            HStack {
                ProgressView()
                    .scaleEffect(0.5)
                Text("Loading metadata...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 100)
        } else {
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<4) { index in
                    if index < viewModel.filterCriteria.visibleColumns.count {
                        let type = viewModel.filterCriteria.visibleColumns[index]
                        DynamicMetadataColumn(
                            type: type,
                            viewModel: viewModel,
                            index: index
                        )
                        if index < 3 {
                            Divider()
                        }
                    }
                }
            }
            .frame(height: 150)
        }
    }
}

struct DynamicMetadataColumn: View {
    let type: FilterCriteria.MetadataType
    @ObservedObject var viewModel: MainViewModel
    let index: Int
    
    var items: [String] {
        switch type {
        case .date: return viewModel.availableDates
        case .fileType: return viewModel.availableFileTypes
        case .maker: return viewModel.availableMakers
        case .camera: return viewModel.availableCameras
        case .lens: return viewModel.availableLenses
        case .iso: return viewModel.availableISOs
        case .shutterSpeed: return viewModel.availableShutterSpeeds
        case .aperture: return viewModel.availableApertures
        case .focalLength: return viewModel.availableFocalLengths
        }
    }
    
    var selection: Binding<Set<String>> {
        switch type {
        case .date: return $viewModel.filterCriteria.selectedDates
        case .fileType: return $viewModel.filterCriteria.selectedFileTypes
        case .maker: return $viewModel.filterCriteria.selectedMakers
        case .camera: return $viewModel.filterCriteria.selectedCameras
        case .lens: return $viewModel.filterCriteria.selectedLenses
        case .iso: return $viewModel.filterCriteria.selectedISOs
        case .shutterSpeed: return $viewModel.filterCriteria.selectedShutterSpeeds
        case .aperture: return $viewModel.filterCriteria.selectedApertures
        case .focalLength: return $viewModel.filterCriteria.selectedFocalLengths
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with Menu
            Menu {
                ForEach(FilterCriteria.MetadataType.allCases) { metaType in
                    Button(metaType.rawValue) {
                        viewModel.filterCriteria.visibleColumns[index] = metaType
                    }
                }
            } label: {
                HStack {
                    Text(type.rawValue)
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .padding(.leading, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .background(Color.secondary.opacity(0.1))
            
            // List
            List {
                ForEach(items, id: \.self) { (item: String) in
                    HStack {
                        Text(item)
                        Spacer()
                        if selection.wrappedValue.contains(item) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selection.wrappedValue.contains(item) {
                            selection.wrappedValue.remove(item)
                        } else {
                            selection.wrappedValue.insert(item)
                        }
                        viewModel.applyFilter()
                    }
                }
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 100)
    }
}
