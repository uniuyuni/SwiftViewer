import SwiftUI
import AppKit

struct FolderNodeView: View {
    let folder: FileItem
    @ObservedObject var viewModel: MainViewModel
    
    // Use a binding to the set in ViewModel
    var isExpanded: Binding<Bool> {
        Binding(
            get: { viewModel.expandedFolders.contains(folder.url.path) },
            set: { isExpanded in
                if isExpanded {
                    viewModel.expandedFolders.insert(folder.url.path)
                } else {
                    viewModel.expandedFolders.remove(folder.url.path)
                }
            }
        )
    }
    
    @State private var subfolders: [FileItem]? = nil
    
    // Alert States
    @State private var showRenameAlert = false
    @State private var newFolderName = ""
    
    @State private var showNewFolderAlert = false
    @State private var newSubFolderName = ""
    
    @State private var showDeleteAlert = false
    
    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            if let subfolders = subfolders {
                ForEach(subfolders) { subfolder in
                    FolderNodeView(folder: subfolder, viewModel: viewModel)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading)
            }
        } label: {
            NavigationLink(value: folder) {
                HStack {
                    Label(folder.name, systemImage: "folder")
                    if let count = folder.fileCount {
                        Text("(\(count))")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            .draggable(folder.url)
            .onDrop(of: [.fileURL], delegate: FolderDropDelegate(targetFolder: folder, viewModel: viewModel))
            .contextMenu {
                Button("Rename") {
                    newFolderName = folder.name
                    showRenameAlert = true
                }
                
                Button("New Folder...") {
                    newSubFolderName = ""
                    showNewFolderAlert = true
                }
                
                Divider()
                
                Button("Delete", role: .destructive) {
                    showDeleteAlert = true
                }
            }
            .alert("Rename Folder", isPresented: $showRenameAlert) {
                TextField("New Name", text: $newFolderName)
                Button("Rename") {
                    if !newFolderName.isEmpty {
                        viewModel.renameFolder(url: folder.url, newName: newFolderName)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("New Folder", isPresented: $showNewFolderAlert) {
                TextField("Folder Name", text: $newSubFolderName)
                Button("Create") {
                    if !newSubFolderName.isEmpty {
                        viewModel.createFolder(at: folder.url, name: newSubFolderName)
                        // Expand to show new folder
                        isExpanded.wrappedValue = true
                        loadSubfolders() // Trigger reload
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Delete Folder", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    viewModel.deleteFolder(folder.url)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete '\(folder.name)'? This cannot be undone.")
            }
        }
        .onChange(of: isExpanded.wrappedValue) { expanded in
            if expanded && subfolders == nil {
                loadSubfolders()
            }
        }
        .onChange(of: viewModel.fileSystemRefreshID) { _ in
            if isExpanded.wrappedValue {
                loadSubfolders()
            }
        }
        .onAppear {
            if isExpanded.wrappedValue && subfolders == nil {
                loadSubfolders()
            }
            checkExpansion()
        }
        .onChange(of: viewModel.currentFolder) { _ in
            checkExpansion()
        }
    }
    
    private func checkExpansion() {
        guard !isExpanded.wrappedValue else { return }
        guard let current = viewModel.currentFolder else { return }
        
        let folderPath = folder.url.standardizedFileURL.path
        let currentPath = current.url.standardizedFileURL.path
        
        if currentPath.hasPrefix(folderPath) && currentPath != folderPath {
            if currentPath.hasPrefix(folderPath + "/") {
                isExpanded.wrappedValue = true
            }
        }
    }
    
    private func loadSubfolders() {
        let url = folder.url
        Task.detached(priority: .userInitiated) {
            let items = FileSystemService.shared.getContentsOfDirectory(at: url, calculateCounts: true)
            let folders = items.filter { $0.isDirectory }
            
            await MainActor.run {
                self.subfolders = folders
            }
        }
    }
}

struct FolderDropDelegate: DropDelegate {
    let targetFolder: FileItem
    let viewModel: MainViewModel
    
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.fileURL])
    }
    
    func dropEntered(info: DropInfo) {
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        let modifiers = NSApp.currentEvent?.modifierFlags
        let isOptionPressed = modifiers?.contains(.option) ?? false
        
        if isOptionPressed {
            return DropProposal(operation: .copy)
        }
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        
        // Capture modifiers synchronously on Main Thread
        let modifiers = NSApp.currentEvent?.modifierFlags
        let isOptionPressed = modifiers?.contains(.option) ?? false
        let isCommandPressed = modifiers?.contains(.command) ?? false
        
        // We only need to check the first item to determine if it's a selection drag
        _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url else { return }
            
            Task {
                await MainActor.run {
                    // Check if the dropped URL is part of the current selection
                    // If so, we move/copy ALL selected files
                    var itemsToProcess: [FileItem] = []
                    
                    // Helper to create FileItem from URL
                    func fileItem(for url: URL) -> FileItem {
                        var isDir: ObjCBool = false
                        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                        return FileItem(url: url, isDirectory: isDir.boolValue, isAvailable: exists)
                    }
                    
                    if viewModel.selectedFiles.contains(where: { $0.url == url }) {
                        // It is in selection, use the whole selection
                        itemsToProcess = Array(viewModel.selectedFiles)
                    } else {
                        // Not in selection, just process this one
                        itemsToProcess = [fileItem(for: url)]
                    }
                    
                    let sourceValues = try? url.resourceValues(forKeys: [.volumeIdentifierKey])
                    let destValues = try? targetFolder.url.resourceValues(forKeys: [.volumeIdentifierKey])
                    
                    let sourceVol = sourceValues?.volumeIdentifier as? NSObject
                    let destVol = destValues?.volumeIdentifier as? NSObject
                    let isSameVolume = (sourceVol != nil && destVol != nil && sourceVol == destVol)
                    
                    if isOptionPressed {
                        viewModel.requestCopyFiles(itemsToProcess, to: targetFolder.url)
                    } else if isSameVolume {
                        viewModel.requestMoveFiles(itemsToProcess, to: targetFolder.url)
                    } else {
                        // Different volume default is Copy
                        if isCommandPressed {
                            viewModel.requestMoveFiles(itemsToProcess, to: targetFolder.url)
                        } else {
                            viewModel.requestCopyFiles(itemsToProcess, to: targetFolder.url)
                        }
                    }
                }
            }
        }
        return true
    }
}
