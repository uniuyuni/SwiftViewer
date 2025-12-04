import SwiftUI

public struct MainWindow: View {
    @StateObject private var viewModel = MainViewModel()

    
    public init() {}
    
    public var body: some View {
        mainContent
            .task {
                await viewModel.loadRootFolders()
            }
            // Global Quick Look Shortcut
            .background(
                Button("Quick Look") {
                    let urls: [URL]
                    if !viewModel.selectedFiles.isEmpty {
                        urls = viewModel.selectedFiles.map { $0.url }
                    } else if let item = viewModel.currentFile {
                        urls = [item.url]
                    } else {
                        urls = []
                    }
                    
                    if !urls.isEmpty {
                        QuickLookService.shared.toggleQuickLook(for: urls)
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                .hidden()
            )
            .onAppear {
                NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.keyCode == 49 { // Space
                        // Avoid interfering with text editing
                        if let _ = NSApp.keyWindow?.firstResponder as? NSTextView {
                            return event
                        }
                        
                        // Trigger Quick Look
                        Task { @MainActor in
                            let urls: [URL]
                            if !viewModel.selectedFiles.isEmpty {
                                urls = viewModel.selectedFiles.map { $0.url }
                            } else if let item = viewModel.currentFile {
                                urls = [item.url]
                            } else {
                                urls = []
                            }
                            
                            if !urls.isEmpty {
                                QuickLookService.shared.toggleQuickLook(for: urls)
                            }
                        }
                        return nil // Consume event
                    }
                    return event
                }
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $viewModel.columnVisibility) {
                SidebarView(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 150, ideal: 200, max: 400)
            } detail: {
                detailContent
            }
            .frame(minWidth: 900, minHeight: 600) // Reduced minWidth
            .onChange(of: viewModel.currentFolder) { _, newFolder in
                if let folder = newFolder {
                    viewModel.openFolder(folder)
                }
            }
            .onChange(of: viewModel.currentCatalog) { _, newCatalog in
                if let catalog = newCatalog {
                    viewModel.openCatalog(catalog)
                }
            }
            .background {
                hiddenControls
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: { viewModel.toggleInspector() }) {
                        Label("Inspector", systemImage: "info.circle")
                    }
                    
                    Button(action: { viewModel.isPreviewVisible.toggle() }) {
                        Label("Preview", systemImage: "eye")
                    }
                }
                
                ToolbarItemGroup {
                    Slider(value: $viewModel.thumbnailSize, in: 50...300)
                        .frame(width: 100)
                }
            }
            .onChange(of: viewModel.filterCriteria.minRating) { _, _ in viewModel.applyFilter() }
            .onChange(of: viewModel.filterCriteria.colorLabel) { _, _ in viewModel.applyFilter() }
            .focusedSceneValue(\.toggleInspector) {
                withAnimation {
                    viewModel.toggleInspector()
                }
            }
            .focusedSceneValue(\.updateCatalog) {
                viewModel.triggerCatalogUpdateCheck()
            }
            .modifier(MainWindowAlerts(viewModel: viewModel))
            
            if viewModel.isBlockingOperation {
                BlockingOperationView(
                    message: viewModel.blockingOperationMessage,
                    progress: viewModel.blockingOperationProgress
                )
                .zIndex(100) // Ensure it's on top
            }
        }
    }
    
    @ViewBuilder
    private var detailContent: some View {
        HStack(spacing: 0) {
            PersistentSplitView(
                autosaveName: "MainSplitView",
                isVertical: true,
                hideSecondPane: !viewModel.isPreviewVisible
            ) {
                GridView(viewModel: viewModel)
            } content2: {
                DetailView(viewModel: viewModel)
            }
            
            if viewModel.isInspectorVisible {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                
                InspectorView(viewModel: viewModel)
                    .frame(width: 280)
                    .transition(.move(edge: .trailing))
            }
        }
    }
    
    @ViewBuilder
    private var blockingOverlay: some View {
        if viewModel.isBlockingOperation {
            BlockingOperationView(
                message: viewModel.blockingOperationMessage,
                progress: viewModel.blockingOperationProgress
            )
        }
    }
    
    @ViewBuilder
    private var hiddenControls: some View {
        // Inspector toggle moved to FocusedValue
        
        // Refresh button removed to avoid conflict with App-level command.
        // App-level command handles refresh via NotificationCenter.
        
        Button("Reveal in Finder") {
            if let url = viewModel.currentFile?.url {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .hidden()
        
        Button("Refresh All") {
            viewModel.refreshAll()
        }
        .keyboardShortcut("r", modifiers: .command)
        .hidden()
        
        Button("") { viewModel.selectNext() }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .hidden()
        
        Button("") { viewModel.selectPrevious() }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .hidden()
            
        Button("Select All") { viewModel.selectAll() }
            .keyboardShortcut("a", modifiers: .command)
            .hidden()

        Button("Toggle Layout") { viewModel.togglePreviewLayout() }
            .keyboardShortcut(.tab, modifiers: .shift)
            .hidden()
        
        // Favorite and Flag shortcuts (Catalog only)
        Button("Toggle Favorite") {
            if viewModel.appMode == .catalog {
                let items = viewModel.selectedFiles.isEmpty ? (viewModel.currentFile.map { [$0] } ?? []) : Array(viewModel.selectedFiles)
                if !items.isEmpty {
                    viewModel.toggleFavorite(for: items)
                }
            }
        }
        .keyboardShortcut("l", modifiers: [])
        .hidden()
        
        Button("Set Pick Flag") {
            if viewModel.appMode == .catalog {
                let items = viewModel.selectedFiles.isEmpty ? (viewModel.currentFile.map { [$0] } ?? []) : Array(viewModel.selectedFiles)
                if !items.isEmpty {
                    viewModel.setFlagStatus(for: items, status: 1)
                }
            }
        }
        .keyboardShortcut("a", modifiers: [])
        .hidden()
        
        Button("Set Reject Flag") {
            if viewModel.appMode == .catalog {
                let items = viewModel.selectedFiles.isEmpty ? (viewModel.currentFile.map { [$0] } ?? []) : Array(viewModel.selectedFiles)
                if !items.isEmpty {
                    viewModel.setFlagStatus(for: items, status: -1)
                }
            }
        }
        .keyboardShortcut("x", modifiers: [])
        .hidden()
        
        Button("Unflag") {
            if viewModel.appMode == .catalog {
                let items = viewModel.selectedFiles.isEmpty ? (viewModel.currentFile.map { [$0] } ?? []) : Array(viewModel.selectedFiles)
                if !items.isEmpty {
                    viewModel.setFlagStatus(for: items, status: 0)
                }
            }
        }
        .keyboardShortcut("u", modifiers: [])
        .hidden()
    }
}

struct MainWindowAlerts: ViewModifier {
    @ObservedObject var viewModel: MainViewModel
    
    func body(content: Content) -> some View {
        content
            .alert("Move Files", isPresented: $viewModel.showMoveFilesConfirmation) {
                Button("Move", role: .destructive) {
                    viewModel.confirmMoveFiles()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let dest = viewModel.fileOpDestination {
                    Text("Are you sure you want to move \(viewModel.filesToMove.count) files to \"\(dest.lastPathComponent)\"?")
                } else {
                    Text("Are you sure you want to move these files?")
                }
            }
            .alert("Copy Files", isPresented: $viewModel.showCopyFilesConfirmation) {
                Button("Copy") {
                    viewModel.confirmCopyFiles()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let dest = viewModel.fileOpDestination {
                    Text("Are you sure you want to copy \(viewModel.filesToCopy.count) files to \"\(dest.lastPathComponent)\"?")
                } else {
                    Text("Are you sure you want to copy these files?")
                }
            }
            .alert("Update Catalog", isPresented: $viewModel.showUpdateConfirmation) {
                if let stats = viewModel.updateStats, !stats.metadataMismatches.isEmpty {
                    Button("Update (Use Catalog Settings)", role: .destructive) {
                        if let catalog = viewModel.catalogToUpdate {
                            viewModel.performCatalogUpdate(catalog: catalog, stats: stats, strategy: .preferCatalog)
                        }
                    }
                    Button("Update (Use File Settings)") {
                        if let catalog = viewModel.catalogToUpdate {
                            viewModel.performCatalogUpdate(catalog: catalog, stats: stats, strategy: .preferFile)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("Update", role: .destructive) {
                        if let catalog = viewModel.catalogToUpdate, let stats = viewModel.updateStats {
                            viewModel.performCatalogUpdate(catalog: catalog, stats: stats)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } message: {
                if let stats = viewModel.updateStats {
                    if !stats.metadataMismatches.isEmpty {
                        Text("Found changes:\nAdded: \(stats.added.count)\nDeleted: \(stats.removed.count)\nUpdated: \(stats.updated.count)\n\nMetadata Mismatches: \(stats.metadataMismatches.count)\n\nThere are metadata conflicts. Choose 'Use Catalog Settings' to overwrite files with catalog data, or 'Use File Settings' to update catalog from files.")
                    } else {
                        Text("Found changes:\nAdded: \(stats.added.count)\nDeleted: \(stats.removed.count)\nUpdated: \(stats.updated.count)")
                    }
                } else {
                    Text("Scanning...")
                }
            }
    }
}


