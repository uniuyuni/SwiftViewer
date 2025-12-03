import SwiftUI

struct SimpleFolderTreeView: View {
    let rootFolders: [FileItem]
    @Binding var selectedFolder: URL?
    @Binding var expandedFolders: Set<URL> // Added binding
    var virtualFolders: [FileItem] = []
    var isLoading: Bool = false // Added loading state
    var viewModel: AdvancedCopyViewModel? = nil
    
    var body: some View {
        List {
            ForEach(rootFolders) { folder in
                SimpleFolderNodeView(folder: folder, selectedFolder: $selectedFolder, expandedFolders: $expandedFolders, virtualFolders: virtualFolders, isLoading: isLoading, viewModel: viewModel)
            }
        }
    }
}

struct SimpleFolderNodeView: View {
    let folder: FileItem
    @Binding var selectedFolder: URL?
    @Binding var expandedFolders: Set<URL>
    var virtualFolders: [FileItem]
    var isLoading: Bool
    var viewModel: AdvancedCopyViewModel? = nil
    
    @State private var subfolders: [FileItem]? = nil
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    
    var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedFolders.contains(folder.url) },
            set: { isExpanded in
                if isExpanded {
                    expandedFolders.insert(folder.url)
                    if subfolders == nil {
                        loadSubfolders()
                    }
                } else {
                    expandedFolders.remove(folder.url)
                }
            }
        )
    }
    
    var body: some View {
        if folder.isAvailable {
            DisclosureGroup(isExpanded: isExpanded) {
                if let subfolders = subfolders {
                    // Merge real subfolders with virtual ones that belong here
                    let combined = mergeSubfolders(real: subfolders, virtual: virtualFolders, parent: folder.url)
                    
                    ForEach(combined) { subfolder in
                        SimpleFolderNodeView(folder: subfolder, selectedFolder: $selectedFolder, expandedFolders: $expandedFolders, virtualFolders: virtualFolders, isLoading: isLoading, viewModel: viewModel)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading)
                        .onAppear {
                            if expandedFolders.contains(folder.url) {
                                loadSubfolders()
                            }
                        }
                }
            } label: {
                folderContent
            }
        } else {
            // Virtual folder (not expandable)
            folderContent
                // No padding for virtual folders to align with real subfolders
                // .padding(.leading, 12)
        }
    }
    
    private var folderContent: some View {
        Button {
            if folder.isAvailable {
                selectedFolder = folder.url
            }
        } label: {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(folder.isAvailable ? .blue : .gray)
                Text(folder.name)
                    .foregroundColor(folder.isConflict ? .red : (folder.isAvailable ? .primary : .secondary))
                
                if isLoading && selectedFolder == folder.url {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
                
                Spacer()
                if selectedFolder == folder.url {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
        .onReceive(NotificationCenter.default.publisher(for: .refreshFileSystem)) { _ in
            if isExpanded.wrappedValue {
                loadSubfolders()
            }
        }
        .disabled(!folder.isAvailable)
        .contextMenu {
            // Only show menu for real folders
            if folder.isAvailable && viewModel != nil {
                Button("New Folder...") {
                    newFolderName = ""
                    showNewFolderAlert = true
                }
            }
        }
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder Name", text: $newFolderName)
            Button("Create") {
                if !newFolderName.isEmpty, let viewModel = viewModel {
                    viewModel.createFolder(at: folder.url, name: newFolderName)
                    // Expand to show new folder
                    isExpanded.wrappedValue = true
                    loadSubfolders()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    private func mergeSubfolders(real: [FileItem], virtual: [FileItem], parent: URL) -> [FileItem] {
        guard !virtual.isEmpty else { return real }
        
        // Filter virtual folders that belong to this parent
        let parentPath = parent.standardizedFileURL.path
        
        let belongingVirtual = virtual.filter { item in
            let itemParent = item.url.deletingLastPathComponent().standardizedFileURL.path
            return itemParent == parentPath
        }
        
        if belongingVirtual.isEmpty {
            return real
        }
        
        // Deduplicate: 
        // If a virtual folder exists in real folders:
        // - If virtual is a CONFLICT (Red), we want to show the CONFLICT version (Red).
        // - If virtual is NOT a conflict (e.g. just predicted), we prefer the REAL version (Normal).
        
        var merged = real
        
        for v in belongingVirtual {
            if let index = merged.firstIndex(where: { $0.url.standardizedFileURL.path == v.url.standardizedFileURL.path }) {
                // Exists in real
                if v.isConflict {
                    // Replace real with conflict (Red)
                    merged[index] = v
                }
                // Else: Keep real
            } else {
                // Does not exist in real, add virtual
                merged.append(v)
            }
        }
        
        return merged.sorted { $0.name < $1.name }
    }
    
    private func loadSubfolders() {
        Task {
            // Add a timeout to prevent infinite spinner
            let task = Task {
                // FileSystemService methods are now nonisolated (synchronous but thread-safe for reads)
                let items = FileSystemService.shared.getContentsOfDirectory(at: folder.url)
                let folders = items.filter { $0.isDirectory }
                await MainActor.run {
                    self.subfolders = folders
                }
            }
            
            // Wait for result or timeout (manual timeout logic)
            // Since we can't easily timeout a Task without structured concurrency's withTaskGroup or similar which is complex here,
            // we will just let it run. The "hang" might be because it never returns.
            // But FileSystemService uses FileManager, which shouldn't hang indefinitely unless network drive.
            // Let's add a failsafe timeout using Task.sleep
            
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds timeout
            
            await MainActor.run {
                if self.subfolders == nil {
                    // Timeout occurred or still loading
                    Logger.shared.log("SimpleFolderTreeView: Loading subfolders timed out for \(folder.name)")
                    self.subfolders = [] // Stop spinner
                    task.cancel()
                }
            }
        }
    }
}
