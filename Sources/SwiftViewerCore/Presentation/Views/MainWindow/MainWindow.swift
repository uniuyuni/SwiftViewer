import SwiftUI

public struct MainWindow: View {
    @StateObject private var viewModel = MainViewModel()
    
    @State private var detailWidth: CGFloat = 300
    
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

    
    private var mainContent: some View {
        NavigationSplitView(columnVisibility: $viewModel.columnVisibility) {
            SidebarView(viewModel: viewModel)
        } content: {
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    GridView(viewModel: viewModel)
                        .frame(minWidth: 0, maxWidth: .infinity)
                    
                    if viewModel.isPreviewVisible {
                        // Spacer for splitter width (1px visual)
                        Color.clear.frame(width: 1)
                        
                        DetailView(viewModel: viewModel)
                            .frame(width: detailWidth)
                    }
                    
                    if viewModel.isInspectorVisible {
                        // Inspector moved to detail block
                    }
                }
                
                // Splitter Overlay
                if viewModel.isPreviewVisible {
                    HStack(spacing: 0) {
                        Spacer() // Push to right of GridView
                        DraggableSplitter(width: $detailWidth)
                        Spacer().frame(width: detailWidth) // Push left by detailWidth
                    }
                }
            }
        } detail: {
            if viewModel.isInspectorVisible {
                InspectorView(viewModel: viewModel)
            }
        }
        .frame(minWidth: 500, minHeight: 400) // Reduced minWidth
        .onChange(of: viewModel.currentFolder) { newFolder in
            if let folder = newFolder {
                viewModel.openFolder(folder)
            }
        }
        .onChange(of: viewModel.currentCatalog) { newCatalog in
            if let catalog = newCatalog {
                viewModel.openCatalog(catalog)
            }
        }
        .background {
            hiddenControls
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Slider(value: $viewModel.thumbnailSize, in: 50...300)
                    .frame(width: 100)
            }
        }
        .onChange(of: viewModel.filterCriteria.minRating) { _ in viewModel.applyFilter() }
        .onChange(of: viewModel.filterCriteria.colorLabel) { _ in viewModel.applyFilter() }
        .focusedSceneValue(\.toggleInspector) {
            withAnimation {
                viewModel.toggleInspector()
            }
        }
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
    }
}

struct DraggableSplitter: View {
    @Binding var width: CGFloat
    
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 40) // Hit area increased to 40px
            )
            .zIndex(1) // Ensure it's above other content
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newWidth = width - value.translation.width
                        // Clamp - Relaxed constraints
                        if newWidth >= 100 && newWidth <= 2000 {
                            width = newWidth
                        }
                    }
            )
    }
}
