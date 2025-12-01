import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: MainViewModel
    
    @State private var showCatalogManager = false
    @State private var showImportView = false
    
    var body: some View {
        let selectionBinding = Binding<FileItem?>(
            get: { viewModel.currentFolder },
            set: { folder in
                if let folder = folder {
                    viewModel.openFolder(folder)
                } else {
                    viewModel.currentFolder = nil
                }
            }
        )
        
        List(selection: selectionBinding) {
            if viewModel.appMode == .catalog {
                Section("Collections") {
                    ForEach(viewModel.collections) { collection in
                        Button {
                            viewModel.openCollection(collection)
                        } label: {
                            Label(collection.name ?? "Untitled", systemImage: "rectangle.stack")
                        }
                        .contextMenu {
                            Button("Rename") {
                                collectionToRename = collection
                                newCollectionName = collection.name ?? ""
                                showCollectionRenameAlert = true
                            }
                            Button("Delete Collection", role: .destructive) {
                                viewModel.deleteCollection(collection)
                            }
                        }
                    }
                    
                    Button {
                        viewModel.createCollection(name: "New Collection \(Int(Date().timeIntervalSince1970))")
                    } label: {
                        Label("New Collection", systemImage: "plus")
                    }
                }
            }
            
            CatalogSection(viewModel: viewModel, showCatalogManager: $showCatalogManager, showImportView: $showImportView, folderToRename: $folderToRename, newFolderName: $newFolderName, showRenameAlert: $showRenameAlert)
            
            LocationsSection(viewModel: viewModel, folderToRename: $folderToRename, newFolderName: $newFolderName, showRenameAlert: $showRenameAlert)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .debugSize()
        .navigationTitle(viewModel.currentCollection?.name ?? viewModel.currentCatalog?.name ?? "SwiftViewer")
        .sheet(isPresented: $showCatalogManager) {
            CatalogManagerView(selectedCatalog: $viewModel.currentCatalog)
        }
        .sheet(isPresented: $showImportView) {
            if let catalog = viewModel.currentCatalog {
                ImportView(viewModel: ImportViewModel(catalog: catalog), mainViewModel: viewModel)
                    .onDisappear {
                        // Refresh items after import
                        viewModel.openCatalog(catalog)
                    }
            }
        }
        .alert("Rename Folder", isPresented: $showRenameAlert) {
            TextField("New Name", text: $newFolderName)
            Button("Rename") {
                if let url = folderToRename, !newFolderName.isEmpty {
                    viewModel.renameFolder(url: url, newName: newFolderName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Collection", isPresented: $showCollectionRenameAlert) {
            TextField("New Name", text: $newCollectionName)
            Button("Rename") {
                if let collection = collectionToRename, !newCollectionName.isEmpty {
                    viewModel.renameCollection(collection, newName: newCollectionName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Move Folder", isPresented: $viewModel.showMoveConfirmation) {
            Button("Move", role: .destructive) {
                viewModel.confirmMoveFolder()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let source = viewModel.moveSourceURL, let dest = viewModel.moveDestinationURL {
                Text("Are you sure you want to move '\(source.lastPathComponent)' to '\(dest.lastPathComponent)'?")
            } else {
                Text("Are you sure you want to move this folder?")
            }
        }
        .alert("Copy Folder", isPresented: $viewModel.showCopyConfirmation) {
            Button("Copy") {
                viewModel.confirmCopyFolder()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let source = viewModel.copySourceURL, let dest = viewModel.copyDestinationURL {
                Text("Are you sure you want to copy '\(source.lastPathComponent)' to '\(dest.lastPathComponent)'?")
            } else {
                Text("Are you sure you want to copy this folder?")
            }
        }
        .refreshableCommand {
            refresh()
        }
        .safeAreaInset(edge: .bottom) {
            thumbnailStatusView
        }
    }
    
    @ObservedObject private var thumbnailService = ThumbnailGenerationService.shared
    
    @ViewBuilder
    private var thumbnailStatusView: some View {
        if thumbnailService.isGenerating {
            VStack(spacing: 4) {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                    Text(thumbnailService.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                
                // Always show progress bar if generating
                ProgressView(value: thumbnailService.progress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
            }
            .padding()
            .background(.regularMaterial)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(nsColor: .separatorColor)), alignment: .top)
        }
    }
    
    @State private var showRenameAlert = false
    @State private var folderToRename: URL?
    @State private var newFolderName = ""
    
    @State private var showCollectionRenameAlert = false
    @State private var collectionToRename: Collection?
    @State private var newCollectionName = ""
    
    private func refresh() {
        Task {
            if let folder = viewModel.currentFolder {
                // refreshFileAttributes is internal/public but takes a URL
                await viewModel.refreshFileAttributes(for: folder.url)
            }
        }
    }
}

// Helper to add keyboard shortcut
struct RefreshCommandModifier: ViewModifier {
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .background(
                Button("Refresh") {
                    action()
                }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0)
            )
    }
}

extension View {
    func refreshableCommand(action: @escaping () -> Void) -> some View {
        self.modifier(RefreshCommandModifier(action: action))
    }
}

struct CatalogSection: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var showCatalogManager: Bool
    @Binding var showImportView: Bool
    @Binding var folderToRename: URL?
    @Binding var newFolderName: String
    @Binding var showRenameAlert: Bool
    
    @State private var showUpdateConfirmation = false
    @State private var updateStats: MainViewModel.CatalogUpdateStats?
    @State private var catalogToUpdate: Catalog?
    
    var body: some View {
        Section("Catalogs") {
            Button("Manage Catalogs") {
                showCatalogManager = true
            }
            
            if let catalog = viewModel.currentCatalog {
                HStack {
                    Button {
                        viewModel.openCatalog(catalog)
                    } label: {
                        Label(catalog.name ?? "Untitled", systemImage: "book.closed.fill")
                    }
                    .buttonStyle(.plain)
                    
                    if viewModel.isScanningCatalog {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                }
                .contextMenu {
                    Button("Update Catalog") {
                        catalogToUpdate = catalog
                        Task {
                            let stats = await viewModel.checkForUpdates(catalog: catalog)
                            updateStats = stats
                            showUpdateConfirmation = true
                        }
                    }
                    
                    Button("Rename") {
                        // Implement catalog rename if needed (not requested but good practice)
                    }
                }
                .alert("Update Catalog", isPresented: $showUpdateConfirmation) {
                    Button("Update", role: .destructive) { // Destructive because it deletes files from DB
                        if let catalog = catalogToUpdate, let stats = updateStats {
                            viewModel.performCatalogUpdate(catalog: catalog, stats: stats)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    if let stats = updateStats {
                        Text("Found changes:\nAdded: \(stats.added.count)\nDeleted: \(stats.removed.count)\nUpdated: \(stats.updated.count)")
                    } else {
                        Text("Scanning...")
                    }
                }
                
                Section("Folders") {
                    // Pending Imports
                    if !viewModel.pendingImports.isEmpty {
                        ForEach(viewModel.pendingImports, id: \.self) { url in
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                                Text(url.lastPathComponent)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 2)
                            .padding(.leading, 4)
                        }
                    }
                    
                    if viewModel.catalogRootNodes.isEmpty {
                        Text("No folders")
                            .foregroundStyle(.secondary)
                    } else {
                        CatalogFolderTreeView(nodes: viewModel.catalogRootNodes, viewModel: viewModel, folderToRename: $folderToRename, newFolderName: $newFolderName, showRenameAlert: $showRenameAlert)
                    }
                }
                
                }
                
                Button(action: { showImportView = true }) {
                    Label("Import...", systemImage: "square.and.arrow.down")
                }
                .padding(.leading)
        }
        .dropDestination(for: URL.self) { items, location in
            guard let url = items.first else { return false }
            viewModel.importFolderToCatalog(url: url)
            return true
        }
    }
}

struct LocationsSection: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var folderToRename: URL?
    @Binding var newFolderName: String
    @Binding var showRenameAlert: Bool
    
    var body: some View {
        Section(header: HStack {
            Text("Locations")
            Spacer()
            Button {
                Task {
                    await viewModel.loadRootFolders()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh Devices")
        }) {
            ForEach(viewModel.rootFolders) { folder in
                FolderNodeView(folder: folder, viewModel: viewModel)
            }
        }
    }
}

struct CatalogFolderTreeView: View {
    let nodes: [MainViewModel.CatalogFolderNode]
    @ObservedObject var viewModel: MainViewModel
    @Binding var folderToRename: URL?
    @Binding var newFolderName: String
    @Binding var showRenameAlert: Bool
    
    var body: some View {
        ForEach(nodes) { node in
            CatalogFolderNodeView(node: node, viewModel: viewModel, folderToRename: $folderToRename, newFolderName: $newFolderName, showRenameAlert: $showRenameAlert)
        }
    }
}

struct CatalogFolderNodeView: View {
    let node: MainViewModel.CatalogFolderNode
    @ObservedObject var viewModel: MainViewModel
    @Binding var folderToRename: URL?
    @Binding var newFolderName: String
    @Binding var showRenameAlert: Bool
    @State private var showRemoveConfirmation = false
    
    var isSelected: Bool {
        viewModel.selectedCatalogFolder == node.url
    }
    
    var isExpanded: Binding<Bool> {
        Binding(
            get: { viewModel.expandedCatalogFolders.contains(node.url.path) },
            set: { _ in viewModel.toggleCatalogExpansion(for: node.url) }
        )
    }
    
    var body: some View {
        if let children = node.children, !children.isEmpty {
            DisclosureGroup(isExpanded: isExpanded) {
                CatalogFolderTreeView(nodes: children, viewModel: viewModel, folderToRename: $folderToRename, newFolderName: $newFolderName, showRenameAlert: $showRenameAlert)
            } label: {
                folderContent
            }
        } else {
            folderContent
                .padding(.leading, 12)
        }
    }
    
    var folderContent: some View {
        Button(action: {
            viewModel.selectCatalogFolder(node.url)
        }) {
            HStack {
                Label(node.name, systemImage: "folder")
                    .foregroundStyle(node.isAvailable ? .primary : .secondary)
                if node.fileCount > 0 {
                    Text("(\(node.fileCount))")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .onDrop(of: [.fileURL], delegate: FolderDropDelegate(targetFolder: FileItem(url: node.url, isDirectory: true), viewModel: viewModel))
        .contextMenu {
            Button("Rename") {
                folderToRename = node.url
                newFolderName = node.name
                showRenameAlert = true
            }
            
            Divider()
            
            Button("Remove from Catalog", role: .destructive) {
                showRemoveConfirmation = true
            }
        }
        .alert("Remove Folder", isPresented: $showRemoveConfirmation) {
            Button("Remove", role: .destructive) {
                viewModel.removeFolderFromCatalog(node.url)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove '\(node.name)' from the catalog?")
        }
    }
}
