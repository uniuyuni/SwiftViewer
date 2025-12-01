import SwiftUI

public struct AdvancedCopyView: View {
    @StateObject private var viewModel = AdvancedCopyViewModel()
    // Round 34 Fix: Removed @FetchRequest to prevent crash
    
    public init() {}
    
    @Environment(\.dismiss) private var dismiss
    
    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar / Header
            HStack {
                Text("Advanced Copy")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            HSplitView {
                // Left Pane: Source
                VStack {
                    Text("Source")
                        .font(.subheadline)
                        .padding(.top, 8)
                    SimpleFolderTreeView(rootFolders: viewModel.sourceRootFolders, selectedFolder: $viewModel.selectedSourceFolder, expandedFolders: $viewModel.expandedSourceFolders)
                    
                    Divider()
                    
                    Toggle("Include Subfolders", isOn: $viewModel.includeSubfolders)
                        .padding()
                }
                .frame(minWidth: 200)
                
                // Middle Pane: Files
                VStack {
                    HStack {
                        Text("Files (\(viewModel.files.count))")
                            .font(.headline)
                        
                        Spacer()
                        
                        // Thumbnail Size Slider
                        Image(systemName: "photo")
                            .font(.caption)
                        Slider(value: $viewModel.thumbnailSize, in: 50...300)
                            .frame(width: 100)
                        Image(systemName: "photo.fill")
                            .font(.caption)
                    }
                    .padding(.top)
                    .padding(.horizontal)
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: viewModel.thumbnailSize), spacing: 10)], spacing: 10) {
                            ForEach(viewModel.files) { file in
                                VStack {
                                    AsyncThumbnailView(url: file.url, size: CGSize(width: viewModel.thumbnailSize, height: viewModel.thumbnailSize), id: file.uuid)
                                        .frame(width: viewModel.thumbnailSize, height: viewModel.thumbnailSize)
                                        .clipped()
                                        .cornerRadius(8)
                                        .opacity(file.isAvailable ? 1.0 : 0.5)
                                    
                                    Text(file.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .padding(5)
                                .background(viewModel.selectedFileIDs.contains(file.id) ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(8)
                                .onTapGesture {
                                    if viewModel.selectedFileIDs.contains(file.id) {
                                        viewModel.selectedFileIDs.remove(file.id)
                                    } else {
                                        viewModel.selectedFileIDs.insert(file.id)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
                .frame(minWidth: 300, maxWidth: .infinity)
                .overlay {
                    if viewModel.isLoading {
                        ZStack {
                            Color.black.opacity(0.3)
                            VStack {
                                ProgressView()
                                    .controlSize(.large)
                                Text(viewModel.processingStage)
                                    .foregroundStyle(.white)
                                    .padding(.top, 8)
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                        }
                    }
                }
                
                // Right Pane: Destination
                VStack {
                    Text("Destination")
                        .font(.subheadline)
                        .padding(.top, 8)
                    
                    if viewModel.isLoading {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Updating Preview...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 4)
                    }
                    
                    SimpleFolderTreeView(rootFolders: viewModel.destinationRootFolders, selectedFolder: $viewModel.selectedDestinationFolder, expandedFolders: $viewModel.expandedDestinationFolders, virtualFolders: viewModel.virtualFolders, isLoading: viewModel.isLoading)
                    
                    Divider()
                    
                    // Options
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Options").font(.headline)
                        
                        Toggle("Add to Catalog", isOn: $viewModel.addToCatalog)
                            .disabled(viewModel.catalogs.isEmpty)
                        
                        if viewModel.catalogs.isEmpty {
                            Text("No catalogs available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if viewModel.addToCatalog {
                            Picker("Select Catalog", selection: $viewModel.selectedCatalog) {
                                Text("Select...").tag(nil as Catalog?)
                                ForEach(viewModel.catalogs) { catalog in
                                    Text(catalog.name ?? "Untitled").tag(catalog as Catalog?)
                                }
                            }
                            .labelsHidden()
                            
                            Toggle("Gray out existing files", isOn: $viewModel.grayOutExisting)
                        }
                        
                        Divider()
                        
                        Toggle("Organize by Date (YYYY-MM-DD)", isOn: $viewModel.organizeByDate)
                        
                        if viewModel.organizeByDate {
                            Toggle("Split events", isOn: $viewModel.splitEvents)
                                .padding(.leading)
                            
                            if viewModel.splitEvents {
                                HStack {
                                    Stepper("Gap: \(viewModel.eventSplitGap) min", value: $viewModel.eventSplitGap, in: 1...1440)
                                }
                                .padding(.leading)
                            }
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                }
                .frame(minWidth: 250)
            }
            
            Divider()
            
            // Footer / Actions
            HStack {
                Button("Close") {
                    viewModel.closeWindow()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isCopying)
                
                Spacer()
                
                Text(viewModel.statusMessage)
                    .foregroundStyle(.secondary)
                
                if viewModel.isCopying {
                    ProgressView(value: viewModel.copyProgress)
                        .frame(width: 100)
                }
                
                Button("Copy") {
                    viewModel.performCopy()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isCopying || viewModel.selectedFileIDs.isEmpty || viewModel.selectedDestinationFolder == nil)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onAppear {
            viewModel.refresh()
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            await viewModel.loadRootFolders()
        }
        // Trigger preview updates explicitly when options change
        .onChange(of: viewModel.organizeByDate) { _ in viewModel.updatePreview() }
        .onChange(of: viewModel.splitEvents) { _ in viewModel.updatePreview() }
        .onChange(of: viewModel.eventSplitGap) { _ in viewModel.updatePreview() }
        .onChange(of: viewModel.dateFormat) { _ in viewModel.updatePreview() }
        // For selectedFileIDs, we might want to throttle or debounce, but for now direct update is safer than didSet loop
        .onChange(of: viewModel.selectedFileIDs) { _ in viewModel.updatePreview() }
        .background(WindowAccessor { window in
            if let window = window {
                viewModel.setWindow(window)
            }
        })
    }
}
