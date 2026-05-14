import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var viewModel: MainViewModel

    @State private var showCatalogManager = false

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

        VStack(spacing: 0) {
            SidebarListView(
                viewModel: viewModel,
                selection: selectionBinding,
                showCatalogManager: $showCatalogManager,
                folderToRename: $folderToRename,
                newFolderName: $newFolderName,
                showRenameAlert: $showRenameAlert,
                showCollectionRenameAlert: $showCollectionRenameAlert,
                collectionToRename: $collectionToRename,
                newCollectionName: $newCollectionName,
                showCatalogRenameAlert: $showCatalogRenameAlert,
                catalogToRename: $catalogToRename,
                newCatalogName: $newCatalogName
            )
            .safeAreaInset(edge: .bottom) {
                thumbnailStatusView
            }
        }
        .sheet(isPresented: $showCatalogManager) {
            CatalogManagerView(
                selectedCatalog: $viewModel.currentCatalog, isImporting: viewModel.isImporting
            )
            .interactiveDismissDisabled(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestPresentCatalogManager)) { _ in
            showCatalogManager = true
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
        .alert("Rename Catalog", isPresented: $showCatalogRenameAlert) {
            TextField("New Name", text: $newCatalogName)
            Button("Rename") {
                if let catalog = catalogToRename, !newCatalogName.isEmpty {
                    viewModel.renameCatalog(catalog, newName: newCatalogName)
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
                Text(
                    "Are you sure you want to move '\(source.lastPathComponent)' to '\(dest.lastPathComponent)'?"
                )
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
                Text(
                    "Are you sure you want to copy '\(source.lastPathComponent)' to '\(dest.lastPathComponent)'?"
                )
            } else {
                Text("Are you sure you want to copy this folder?")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshFileSystem)) { _ in
            Task {
                await viewModel.loadRootFolders()
                await MainActor.run {
                    viewModel.fileSystemRefreshID = UUID()
                }

            }
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
            .overlay(
                Rectangle().frame(height: 1).foregroundStyle(Color(nsColor: .separatorColor)),
                alignment: .top)
        }
    }

    @State private var showRenameAlert = false
    @State private var folderToRename: URL?
    @State private var newFolderName = ""

    @State private var showCollectionRenameAlert = false
    @State private var collectionToRename: Collection?
    @State private var newCollectionName = ""

    @State private var showCatalogRenameAlert = false
    @State private var catalogToRename: Catalog?
    @State private var newCatalogName = ""

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

struct CatalogSection: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var showCatalogManager: Bool
    @Binding var folderToRename: URL?
    @Binding var newFolderName: String
    @Binding var showRenameAlert: Bool
    @Binding var showCatalogRenameAlert: Bool
    @Binding var catalogToRename: Catalog?
    @Binding var newCatalogName: String

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

                    if viewModel.isScanningCatalog || viewModel.isSyncingCatalog {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                }
                .contextMenu {
                    Button("Update Catalog") {
                        viewModel.triggerCatalogUpdateCheck(for: catalog)
                    }
                    Button("Optimize Catalog") {
                        viewModel.optimizeCatalog()
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
                        CatalogFolderTreeView(
                            nodes: viewModel.catalogRootNodes, viewModel: viewModel,
                            folderToRename: $folderToRename, newFolderName: $newFolderName,
                            showRenameAlert: $showRenameAlert)
                    }
                }

            }

            Button(action: { viewModel.presentImportDialog() }) {
                Label("Import...", systemImage: "square.and.arrow.down")
            }
            .padding(.leading)
            .disabled(viewModel.currentCatalog == nil || viewModel.isImporting)
        }
        .onDrop(of: [.folder], delegate: CatalogDropDelegate(viewModel: viewModel))
    }
}

struct PhotosLibrarySection: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var showFileImporter = false

    var body: some View {
        Section(
            header: HStack {
                Text("Photos Libraries")
                Spacer()
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
        ) {
            ForEach(viewModel.photosLibraries) { library in
                PhotosLibraryNodeView(library: library, viewModel: viewModel)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter, allowedContentTypes: [.package],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Request access to the folder
                    guard url.startAccessingSecurityScopedResource() else { return }
                    viewModel.addPhotosLibrary(url: url)
                    // Note: We should stop accessing when done, but for a long-lived library reference,
                    // we might need to persist bookmark data. For now, we keep it simple.
                }
            case .failure(let error):
                print("Failed to select Photos Library: \(error)")
            }
        }
    }
}

struct PhotosLibraryNodeView: View {
    let library: PhotosLibrary
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        DisclosureGroup(
            content: {
                if let groups = viewModel.photosLibraryGroups[library.id] {
                    ForEach(groups) { group in
                        PhotosDateGroupNodeView(
                            library: library, group: group, viewModel: viewModel)
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading)
                }
            },
            label: {
                HStack {
                    Image(systemName: "photo.on.rectangle")
                    Text(library.name)
                }
                .contextMenu {
                    Button("Remove Library") {
                        viewModel.removePhotosLibrary(library)
                    }
                }
            }
        )
        .disclosureGroupStyle(CustomSidebarDisclosureStyle())
    }
}

struct PhotosDateGroupNodeView: View {
    let library: PhotosLibrary
    let group: PhotosDateGroup
    @ObservedObject var viewModel: MainViewModel

    var isSelected: Bool {
        viewModel.selectedPhotosGroupID == "\(library.id.uuidString)/\(group.id)"
            && viewModel.currentCollection == nil
    }

    var body: some View {
        HStack {
            Image(systemName: "folder")
            Text(group.id)  // YYYY-MM-DD
            Spacer()
            Text("\(group.assets.count)")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.leading, 12)
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.accentColor : Color.clear)
        .foregroundStyle(isSelected ? .white : .primary)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                await viewModel.selectPhotosGroup(group, libraryID: library.id)
            }
        }
    }
}

struct LocationsSection: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var folderToRename: URL?
    @Binding var newFolderName: String
    @Binding var showRenameAlert: Bool

    var body: some View {
        Section(
            header: HStack {
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
            }
        ) {
            ForEach(viewModel.rootFolders, id: \.url.path) { folder in
                FolderNodeView(folder: folder, viewModel: viewModel, nodePath: "root:\(folder.url.path)")
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
            CatalogFolderNodeView(
                node: node, viewModel: viewModel, folderToRename: $folderToRename,
                newFolderName: $newFolderName, showRenameAlert: $showRenameAlert)
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

    @State private var isExpanded: Bool = false

    var isSelected: Bool {
        viewModel.selectedCatalogFolder?.url == node.url && viewModel.currentCollection == nil
    }

    var body: some View {
        if let children = node.children, !children.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                CatalogFolderTreeView(
                    nodes: children, viewModel: viewModel, folderToRename: $folderToRename,
                    newFolderName: $newFolderName, showRenameAlert: $showRenameAlert)
            } label: {
                folderContent
            }
            .disclosureGroupStyle(CustomSidebarDisclosureStyle())
            .onChange(of: isExpanded) { _, expanded in
                if expanded {
                    viewModel.expandedCatalogFolders.insert(node.url.path)
                } else {
                    viewModel.expandedCatalogFolders.remove(node.url.path)
                }
            }
            .onAppear {
                isExpanded = viewModel.expandedCatalogFolders.contains(node.url.path)
            }
        } else {
            folderContent
                .padding(.leading, 12)
        }
    }

    var folderContent: some View {
        HStack {
            Label(node.name, systemImage: "folder")
                .foregroundStyle(node.isAvailable ? .primary : .secondary)
            if node.fileCount > 0 {
                Text("(\(node.fileCount))")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectCatalogFolder(node.url)
        }
        .onDrag {
            DragState.shared.startDrag(url: node.url)
            return NSItemProvider(object: node.url as NSURL)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.accentColor : Color.clear)
        .foregroundStyle(isSelected ? .white : .primary)
        .cornerRadius(6)
        .onDrop(
            of: [.fileURL],
            delegate: FolderDropDelegate(
                targetFolder: FileItem(url: node.url, isDirectory: true), viewModel: viewModel)
        )
        .contextMenu {
            Button("Update Folder") {
                viewModel.triggerFolderUpdateCheck(folder: node.url)
            }

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

struct CollectionsSectionView: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var showCollectionRenameAlert: Bool
    @Binding var collectionToRename: Collection?
    @Binding var newCollectionName: String

    var body: some View {
        Section("Collections") {
            ForEach(viewModel.collections) { collection in
                let isSelected = viewModel.currentCollection?.id == collection.id
                Button {
                    viewModel.openCollection(collection)
                } label: {
                    Label(collection.name ?? "Untitled", systemImage: "rectangle.stack")
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Color.accentColor : Color.clear)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                // グリッドからコレクションへドラッグ&ドロップで追加（Catalogモードのみ）
                .onDrop(
                    of: [.fileURL],
                    delegate: CollectionDropDelegate(collection: collection, viewModel: viewModel)
                )
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
                viewModel.createCollection(
                    name: "New Collection \(Int(Date().timeIntervalSince1970))")
            } label: {
                Label("New Collection", systemImage: "plus")
            }
        }
    }
}

// MARK: - Collection Drop
struct CollectionDropDelegate: DropDelegate {
    let collection: Collection
    let viewModel: MainViewModel
    
    func validateDrop(info: DropInfo) -> Bool {
        // Collections は Catalog モード前提
        // Photos Library モードでは追加不可（カタログ未登録のため）
        guard !viewModel.isPhotosMode else { return false }
        guard viewModel.appMode == .catalog, viewModel.currentCatalog != nil else { return false }
        return info.hasItemsConforming(to: [.fileURL])
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard !viewModel.isPhotosMode else { return false }
        guard viewModel.appMode == .catalog, viewModel.currentCatalog != nil else { return false }
        
        // 1) 内部ドラッグ（グリッド等）: DragState のURLを起点に、複数選択ならまとめて追加
        if DragState.shared.isValid, let draggedURL = DragState.shared.currentDragSource {
            let isDraggedIncludedInSelection = viewModel.selectedFiles.contains(where: { $0.url == draggedURL })
            let itemsToAdd: [FileItem]
            
            if isDraggedIncludedInSelection, !viewModel.selectedFiles.isEmpty {
                itemsToAdd = Array(viewModel.selectedFiles)
            } else if let single = viewModel.fileItems.first(where: { $0.url == draggedURL }) {
                itemsToAdd = [single]
            } else {
                itemsToAdd = [FileItem(url: draggedURL, isDirectory: false)]
            }
            
            viewModel.addToCollection(itemsToAdd, collection: collection)
            DragState.shared.clear()
            return true
        }
        
        // 2) 外部ドラッグ（Finder等）: fileURLを取り出して追加を試みる（Catalog未登録のファイルは結果的に無視される）
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let u = item as? URL {
                    url = u
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                }
                
                guard let fileURL = url else { return }
                
                Task { @MainActor in
                    self.viewModel.addToCollection([FileItem(url: fileURL, isDirectory: false)], collection: self.collection)
                }
            }
        }
        
        return true
    }
}

struct SidebarListView: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var selection: FileItem?

    @Binding var showCatalogManager: Bool
    @Binding var folderToRename: URL?
    @Binding var newFolderName: String
    @Binding var showRenameAlert: Bool
    @Binding var showCollectionRenameAlert: Bool
    @Binding var collectionToRename: Collection?
    @Binding var newCollectionName: String
    @Binding var showCatalogRenameAlert: Bool
    @Binding var catalogToRename: Catalog?
    @Binding var newCatalogName: String

    var body: some View {
        List(selection: $selection) {
            // Photos Library モードでは、カタログ未登録アイテムが混ざるため Collections を表示しない
            if viewModel.appMode == .catalog && !viewModel.isPhotosMode {
                CollectionsSectionView(
                    viewModel: viewModel, showCollectionRenameAlert: $showCollectionRenameAlert,
                    collectionToRename: $collectionToRename, newCollectionName: $newCollectionName)
            }

            CatalogSection(
                viewModel: viewModel, showCatalogManager: $showCatalogManager,
                folderToRename: $folderToRename, newFolderName: $newFolderName,
                showRenameAlert: $showRenameAlert, showCatalogRenameAlert: $showCatalogRenameAlert,
                catalogToRename: $catalogToRename, newCatalogName: $newCatalogName)

            PhotosLibrarySection(viewModel: viewModel)

            LocationsSection(
                viewModel: viewModel, folderToRename: $folderToRename,
                newFolderName: $newFolderName, showRenameAlert: $showRenameAlert)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .navigationTitle(viewModel.headerTitle)
    }
}

struct CustomSidebarDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    withAnimation {
                        configuration.isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right.square")
                        .foregroundColor(.secondary)
                        .imageScale(.small)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                
                configuration.label
            }
            .padding(.vertical, 2)
            
            if configuration.isExpanded {
                configuration.content
                    .padding(.leading, 12)
            }
        }
    }
}
