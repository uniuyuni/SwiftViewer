import SwiftUI
import AppKit

struct GridView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 10
            let minSize = viewModel.thumbnailSize
            // Round width to nearest 10 pixels to prevent micro-changes
            let roundedWidth = (geo.size.width / 10).rounded() * 10
            let availableWidth = max(0, roundedWidth - 32)
            let columnsCount = max(1, Int((availableWidth + spacing) / (minSize + spacing)))
            
            VStack(spacing: 0) {
                FilterBarView(viewModel: viewModel)
                
                ScrollViewReader { proxy in
                    ScrollView {
                        if viewModel.fileItems.isEmpty {
                            emptyStateView(viewModel: viewModel)
                        } else {
                            gridContent(columnsCount: columnsCount, proxy: proxy)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 400)
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: geo.size.width) { _, width in
                let spacing: CGFloat = 10
                let minSize = viewModel.thumbnailSize
                let availableWidth = max(0, width - 32)
                let cols = max(1, Int((availableWidth + spacing) / (minSize + spacing)))
                
                // Only update if column count actually changes (debounce)
                if viewModel.gridColumnsCount != cols {
                    viewModel.gridColumnsCount = cols
                }
            }
            .onAppear {
                // Initial calculation
                let spacing: CGFloat = 10
                let minSize = viewModel.thumbnailSize
                let availableWidth = max(0, geo.size.width - 32)
                let cols = max(1, Int((availableWidth + spacing) / (minSize + spacing)))
                viewModel.gridColumnsCount = cols
            }
        }
        // Keyboard handling at root level
        .background(
            Button("") {
                viewModel.moveUp()
            }
            .keyboardShortcut(.upArrow, modifiers: [])
            .hidden()
        )
        .background(
            Button("") {
                viewModel.moveDown()
            }
            .keyboardShortcut(.downArrow, modifiers: [])
            .hidden()
        )
        .background(
            Button("") {
                viewModel.moveLeft()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .hidden()
        )
        .background(
            Button("") {
                viewModel.moveRight()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .hidden()
        )
        .refreshableCommand {
            Task {
                await viewModel.refreshFileAttributes()
            }
        }
        .navigationTitle(title)
        .searchable(text: $viewModel.filterCriteria.searchText, placement: .toolbar, prompt: "Search")
        .toolbar {
            toolbarContent
        }
        .onChange(of: viewModel.sortOption) { _, _ in
            viewModel.applyFilter()
        }
        .onChange(of: viewModel.filterCriteria.searchText) { _, _ in
            viewModel.applyFilter()
        }
        .onChange(of: viewModel.isSortAscending) { _, _ in
            viewModel.applyFilter()
        }
        .alert("Delete Items", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                viewModel.performDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to move \(viewModel.itemsToDelete.count) items to the Trash?")
        }
    }

    private var title: String {
        if viewModel.appMode == .catalog {
            if let collection = viewModel.currentCollection {
                return collection.name ?? "Collection"
            } else if let folder = viewModel.selectedCatalogFolder {
                return folder.url.lastPathComponent
            } else if let catalog = viewModel.currentCatalog {
                return catalog.name ?? "Catalog"
            }
        } else {
            if let folder = viewModel.currentFolder {
                return folder.name
            }
        }
        return "SwiftViewer"
    }
    
    @ViewBuilder
    private func gridContent(columnsCount: Int, proxy: ScrollViewProxy) -> some View {
        let spacing: CGFloat = 10
        let minSize = viewModel.thumbnailSize
        
        // Use fixed column count with .flexible to prevent layout recalculation jitter
        let columns = Array(repeating: GridItem(.flexible(minimum: minSize), spacing: spacing), count: columnsCount)
        
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(viewModel.fileItems) { item in
                GridItemWrapper(item: item, viewModel: viewModel)
                    .id(item.id)
            }
        }
        .padding()
        .onChange(of: viewModel.currentFile) { _, newFile in
            if let file = newFile, viewModel.isAutoScrollEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        proxy.scrollTo(file.id, anchor: .center)
                    }
                }
            }
        }
        .onAppear {
            if let file = viewModel.currentFile {
                 DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo(file.id, anchor: .center)
                }
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Sort By", selection: $viewModel.sortOption) {
                    ForEach(MainViewModel.SortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.inline)
                
                Divider()
                
                Button(action: { viewModel.isSortAscending.toggle() }) {
                    Label(viewModel.isSortAscending ? "Ascending" : "Descending", systemImage: viewModel.isSortAscending ? "arrow.up" : "arrow.down")
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }
    }

    
    @ViewBuilder
    @MainActor
    private func emptyStateView(viewModel: MainViewModel) -> some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView {
                Label("No Items", systemImage: "photo.on.rectangle.angled")
            } description: {
                if viewModel.appMode == .catalog {
                    Text("Import photos or videos to get started.")
                } else {
                    Text("Select a folder with images to view them here.")
                }
            }
        } else {
            VStack {
                Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                if viewModel.appMode == .catalog {
                    Text("Import photos or videos to get started.")
                } else {
                    Text("Select a folder with images to view them here.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}

struct GridItemWrapper: View {
    let item: FileItem
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        VStack {
            GridItemView(item: item, viewModel: viewModel)
            
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(5)
        .background(viewModel.selectedFiles.contains(item) ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .contextMenu {
            let targetItems = viewModel.selectedFiles.contains(item) ? Array(viewModel.selectedFiles) : [item]
            
            if viewModel.appMode == .catalog && !viewModel.collections.isEmpty {
                Menu("Add to Collection") {
                    ForEach(viewModel.collections) { collection in
                        Button(collection.name ?? "Untitled") {
                            viewModel.addToCollection(targetItems, collection: collection)
                        }
                    }
                }
            }
            
            Menu("Rating") {
                Button("0 Stars") { viewModel.updateRating(for: targetItems, rating: 0) }
                Button("1 Star") { viewModel.updateRating(for: targetItems, rating: 1) }
                Button("2 Stars") { viewModel.updateRating(for: targetItems, rating: 2) }
                Button("3 Stars") { viewModel.updateRating(for: targetItems, rating: 3) }
                Button("4 Stars") { viewModel.updateRating(for: targetItems, rating: 4) }
                Button("5 Stars") { viewModel.updateRating(for: targetItems, rating: 5) }
            }
            
            Menu("Color Label") {
                Button("None") { viewModel.updateColorLabel(for: targetItems, label: nil) }
                Button("Red") { viewModel.updateColorLabel(for: targetItems, label: "Red") }
                Button("Orange") { viewModel.updateColorLabel(for: targetItems, label: "Orange") }
                Button("Yellow") { viewModel.updateColorLabel(for: targetItems, label: "Yellow") }
                Button("Green") { viewModel.updateColorLabel(for: targetItems, label: "Green") }
                Button("Blue") { viewModel.updateColorLabel(for: targetItems, label: "Blue") }
                Button("Purple") { viewModel.updateColorLabel(for: targetItems, label: "Purple") }
                Button("Gray") { viewModel.updateColorLabel(for: targetItems, label: "Gray") }
            }
            
            Button(viewModel.selectedFiles.first?.isFavorite == true ? "Unfavorite" : "Favorite") {
                viewModel.toggleFavorite(for: targetItems)
            }
            
            Menu("Flag") {
                Button("Flagged") { viewModel.setFlagStatus(for: targetItems, status: 1) }
                Button("Unflagged") { viewModel.setFlagStatus(for: targetItems, status: 0) }
                Button("Rejected") { viewModel.setFlagStatus(for: targetItems, status: -1) }
            }
            
            Divider()
            
            Divider()
            
            Button("Regenerate Thumbnails") {
                viewModel.regenerateThumbnails(for: targetItems)
            }
            
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(targetItems.map { $0.url })
            }
            
            Divider()
            
            Button("Move to Trash", role: .destructive) {
                viewModel.confirmDelete(targetItems)
            }
        }
        .onDrag {
            // Set DragState for internal drag tracking
            DragState.shared.startDrag(url: item.url)
            return NSItemProvider(object: item.url as NSURL)
        }
    }
}

struct GridItemView: View {
    let item: FileItem
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        AsyncThumbnailView(url: item.url, size: CGSize(width: viewModel.thumbnailSize, height: viewModel.thumbnailSize), id: item.uuid, orientation: item.orientation)
            .frame(width: viewModel.thumbnailSize, height: viewModel.thumbnailSize)
            .clipped()
            .overlay {
                ZStack(alignment: .bottomTrailing) {
                    // Selection Indicator
                    if viewModel.selectedFiles.contains(item) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white, .blue)
                            .padding(4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                    
                    // Color Label Indicator
                    if let colorName = viewModel.metadataCache[item.url]?.colorLabel ?? item.colorLabel, let color = colorFromName(colorName) {
                        HStack(spacing: 2) {
                            Circle()
                                .fill(color)
                                .frame(width: 8, height: 8)
                                .background(Circle().fill(.white).frame(width: 10, height: 10))
                            
                            // Flag Indicator (next to color label)
                            if let flagStatus = Optional(viewModel.metadataCache[item.url]?.flagStatus ?? Int(item.flagStatus ?? 0)), flagStatus != 0 {
                                Image(systemName: flagStatus == 1 ? "flag.fill" : "flag.slash.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(flagStatus == 1 ? .green : .red)
                            }
                        }
                        .padding(3)
                        .offset(x: -3, y: -3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else if let flagStatus = Optional(viewModel.metadataCache[item.url]?.flagStatus ?? Int(item.flagStatus ?? 0)), flagStatus != 0 {
                        // Flag Indicator only (no color label)
                        Image(systemName: flagStatus == 1 ? "flag.fill" : "flag.slash.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(flagStatus == 1 ? .green : .red)
                            .padding(3)
                            // Removed white background circle
                            .offset(x: -3, y: -3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    
                    // Rating and Favorite Indicator
                    if let rating = viewModel.metadataCache[item.url]?.rating, rating > 0 {
                        HStack(spacing: 2) {
                            ForEach(0..<rating, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.yellow)
                            }
                            
                            // Favorite Indicator (next to rating)
                            if let isFavorite = viewModel.metadataCache[item.url]?.isFavorite ?? item.isFavorite, isFavorite {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.pink)
                            }
                        }
                        .padding(3)
                        // Removed black background
                        .offset(x: -3, y: 3) // Adjusted to align with top-left
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    } else if let isFavorite = viewModel.metadataCache[item.url]?.isFavorite ?? item.isFavorite, isFavorite {
                        // Favorite Indicator only (no rating)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.pink)
                            .padding(3)
                            // Removed black background
                            .offset(x: -3, y: 3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        .contentShape(Rectangle()) // Ensure tap area covers the whole item
        .contentShape(Rectangle()) // Ensure tap area covers the whole item
        .onTapGesture {
            let modifiers = NSEvent.modifierFlags
            if modifiers.contains(.command) {
                viewModel.toggleSelection(item)
            } else if modifiers.contains(.shift) {
                viewModel.selectRange(to: item)
            } else {
                viewModel.selectFile(item, autoScroll: false)
            }
        }
    }
    
    private func colorFromName(_ name: String) -> Color? {
        switch name.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "gray": return .gray
        default: return nil
        }
    }
}
