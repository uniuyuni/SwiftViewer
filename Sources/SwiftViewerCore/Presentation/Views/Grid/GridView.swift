import SwiftUI
import AppKit

struct GridView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        GeometryReader { geo in
            GridViewContent(viewModel: viewModel, size: geo.size)
        }
        .frame(minWidth: 400) // Applied to GeometryReader to ensure minimum size
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
        .navigationTitle(title)
        .searchable(text: $viewModel.filterCriteria.searchText, placement: .automatic, prompt: "Search")
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
            if viewModel.appMode == .catalog {
                Text("Are you sure you want to remove \(viewModel.itemsToDelete.count) items from the Catalog?")
            } else {
                Text("Are you sure you want to move \(viewModel.itemsToDelete.count) items to the Trash?")
            }
        }
    }

    private var title: String {
        return viewModel.headerTitle
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

}

struct GridViewContent: View {
    @ObservedObject var viewModel: MainViewModel
    let size: CGSize
    
    var body: some View {
        VStack(spacing: 0) {
            FilterBarView(viewModel: viewModel)
            
            ScrollViewReader { proxy in
                ScrollView {
                    if viewModel.fileItems.isEmpty {
                        emptyStateView(viewModel: viewModel)
                    } else {
                        // Use viewModel.gridColumnsCount for dynamic updates
                        gridContent(columnsCount: max(1, viewModel.gridColumnsCount), proxy: proxy)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 400, idealWidth: 600) // Enforce minimum width with ideal size
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: size.width) { _, width in
            let spacing: CGFloat = 10
            let minSize = viewModel.thumbnailSize
            // Increase padding subtraction to account for scrollbar (approx 16px) + padding (32px) -> ~48px
            let availableWidth = max(0, width - 48)
            let cols = max(1, Int((availableWidth + spacing) / (minSize + spacing)))
            
            // Only update if column count actually changes (debounce)
            if viewModel.gridColumnsCount != cols {
                viewModel.gridColumnsCount = cols
            }
        }
        .onChange(of: viewModel.thumbnailSize) { _, _ in
            let spacing: CGFloat = 10
            let minSize = viewModel.thumbnailSize
            let availableWidth = max(0, size.width - 48)
            let cols = max(1, Int((availableWidth + spacing) / (minSize + spacing)))
            viewModel.gridColumnsCount = cols
        }
        .onAppear {
            // Initial calculation
            let spacing: CGFloat = 10
            let minSize = viewModel.thumbnailSize
            let availableWidth = max(0, size.width - 48)
            let cols = max(1, Int((availableWidth + spacing) / (minSize + spacing)))
            viewModel.gridColumnsCount = cols
        }
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
            
            // Metadata editing removed from context menu by user request
            // Use Inspector or Keyboard Shortcuts instead
            
            Divider()
            
            Divider()
            
            Button("Regenerate Thumbnails") {
                viewModel.regenerateThumbnails(for: targetItems)
            }
            
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(targetItems.map { $0.url })
            }
            
            Divider()
            
            if viewModel.appMode == .catalog {
                Button("Remove from Catalog", role: .destructive) {
                    viewModel.confirmDelete(targetItems)
                }
            } else {
                Button("Move to Trash", role: .destructive) {
                    viewModel.confirmDelete(targetItems)
                }
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
                GridItemOverlay(item: item, viewModel: viewModel)
            }
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

struct GridItemOverlay: View {
    let item: FileItem
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        // Check if we should hide metadata overlay (except selection)
        // Hide if in Photos Mode AND item is RAW
        // We assume RAW if not in common compressed formats
        let ext = item.url.pathExtension.lowercased()
        let isRaw = !["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"].contains(ext)
        
        if viewModel.isPhotosMode && isRaw {
            ZStack(alignment: .bottomTrailing) {
                // Selection Indicator ONLY
                if viewModel.selectedFiles.contains(item) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, .blue)
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack(alignment: .bottomTrailing) {
                // Selection Indicator
                if viewModel.selectedFiles.contains(item) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, .blue)
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                
                // Color Label & Flag Indicator
                if let colorName = viewModel.metadataCache[item.url.standardizedFileURL]?.colorLabel ?? item.colorLabel, let color = colorFromName(colorName) {
                    HStack(spacing: 2) {
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                            .background(Circle().fill(.white).frame(width: 10, height: 10))
                        
                        // Flag Indicator (next to color label)
                        if let flagStatus = Optional(viewModel.metadataCache[item.url.standardizedFileURL]?.flagStatus ?? Int(item.flagStatus ?? 0)), flagStatus != 0 {
                            Image(systemName: flagStatus == 1 ? "flag.fill" : "flag.slash.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(flagStatus == 1 ? .green : .red)
                        }
                    }
                    .padding(3)
                    .offset(x: -3, y: -3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if let flagStatus = Optional(viewModel.metadataCache[item.url.standardizedFileURL]?.flagStatus ?? Int(item.flagStatus ?? 0)), flagStatus != 0 {
                    // Flag Indicator only (no color label)
                    Image(systemName: flagStatus == 1 ? "flag.fill" : "flag.slash.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(flagStatus == 1 ? .green : .red)
                        .padding(3)
                        .offset(x: -3, y: -3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                
                // Rating and Favorite Indicator
                if let rating = viewModel.metadataCache[item.url.standardizedFileURL]?.rating ?? item.rating, rating > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<rating, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.yellow)
                        }
                        
                        // Favorite Indicator (next to rating)
                        if let isFavorite = viewModel.metadataCache[item.url.standardizedFileURL]?.isFavorite ?? item.isFavorite, isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.pink)
                        }
                    }
                    .padding(3)
                    .offset(x: -3, y: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                } else if let isFavorite = viewModel.metadataCache[item.url.standardizedFileURL]?.isFavorite ?? item.isFavorite, isFavorite {
                    // Favorite Indicator only (no rating)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.pink)
                        .padding(3)
                        .offset(x: -3, y: 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
