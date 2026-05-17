import SwiftUI
import AppKit

struct UIFolderNode: Identifiable {
    let id: String
    let item: FileItem
}

struct FolderNodeView: View {
    let folder: FileItem
    @ObservedObject var viewModel: MainViewModel
    let nodePath: String

    @State private var isExpanded: Bool = false
    @State private var subNodes: [UIFolderNode]? = nil

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let subNodes = subNodes {
                ForEach(subNodes) { subNode in
                    FolderNodeView(folder: subNode.item, viewModel: viewModel, nodePath: subNode.id)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading)
            }
        } label: {
            HStack {
                Label(folder.name, systemImage: "folder")
                if let count = folder.fileCount {
                    Text("(\(count))")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
            .onDrag {
                DragState.shared.startDrag(url: folder.url)
                return NSItemProvider(object: folder.url as NSURL)
            }
            .onTapGesture {
                viewModel.openFolder(folder)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(viewModel.currentFolder?.url == folder.url && viewModel.appMode == .folders ? Color.accentColor : Color.clear)
            .foregroundStyle(viewModel.currentFolder?.url == folder.url ? .white : .primary)
            .cornerRadius(6)
            .onDrop(of: [.fileURL], delegate: FolderDropDelegate(targetFolder: folder, viewModel: viewModel))
            .overlay(
                FolderContextMenu(
                    onRename: {
                        let folderURL = folder.url
                        let currentName = folder.name
                        DispatchQueue.main.async {
                            let alert = NSAlert()
                            alert.messageText = "Rename Folder"
                            let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
                            tf.stringValue = currentName
                            alert.accessoryView = tf
                            alert.addButton(withTitle: "Rename")
                            alert.addButton(withTitle: "Cancel")
                            alert.window.initialFirstResponder = tf
                            if alert.runModal() == .alertFirstButtonReturn {
                                let newName = tf.stringValue.trimmingCharacters(in: .whitespaces)
                                if !newName.isEmpty {
                                    viewModel.renameFolder(url: folderURL, newName: newName)
                                }
                            }
                        }
                    },
                    onNewFolder: {
                        let folderURL = folder.url
                        DispatchQueue.main.async {
                            let alert = NSAlert()
                            alert.messageText = "New Folder"
                            let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
                            tf.placeholderString = "Folder Name"
                            alert.accessoryView = tf
                            alert.addButton(withTitle: "Create")
                            alert.addButton(withTitle: "Cancel")
                            alert.window.initialFirstResponder = tf
                            if alert.runModal() == .alertFirstButtonReturn {
                                let name = tf.stringValue.trimmingCharacters(in: .whitespaces)
                                if !name.isEmpty {
                                    viewModel.createFolder(at: folderURL, name: name)
                                    isExpanded = true
                                    loadSubfolders()
                                }
                            }
                        }
                    },
                    onMoveToTrash: {
                        let folderURL = folder.url
                        let name = folderURL.lastPathComponent
                        DispatchQueue.main.async {
                            let alert = NSAlert()
                            alert.messageText = "Move to Trash"
                            alert.informativeText = "Move '\(name)' to the Trash?"
                            alert.addButton(withTitle: "Move to Trash")
                            alert.addButton(withTitle: "Cancel")
                            alert.alertStyle = .warning
                            if alert.runModal() == .alertFirstButtonReturn {
                                viewModel.moveFolderToTrash(folderURL)
                            }
                        }
                    }
                )
            )
        }
        .disclosureGroupStyle(CustomSidebarDisclosureStyle())
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                viewModel.expandedFolders.insert(folder.url.path)
                if subNodes == nil {
                    loadSubfolders()
                }
            } else {
                viewModel.expandedFolders.remove(folder.url.path)
            }
        }
        .onChange(of: viewModel.fileSystemRefreshID) { _, _ in
            if isExpanded {
                loadSubfolders()
            }
        }
        .onAppear {
            isExpanded = viewModel.expandedFolders.contains(folder.url.path)
            if isExpanded && subNodes == nil {
                loadSubfolders()
            }
            checkExpansion()
        }
        .onChange(of: viewModel.currentFolder) { _, _ in
            checkExpansion()
        }
    }
    
    private func checkExpansion() {
        guard !isExpanded else { return }
        guard let current = viewModel.currentFolder else { return }
        
        let folderPath = folder.url.standardizedFileURL.path
        let currentPath = current.url.standardizedFileURL.path
        
        if currentPath.hasPrefix(folderPath) && currentPath != folderPath {
            if currentPath.hasPrefix(folderPath + "/") {
                isExpanded = true
            }
        }
    }
    
    private func loadSubfolders() {
        let url = folder.url
        let currentPath = nodePath
        Task.detached(priority: .userInitiated) {
            let items = FileSystemService.shared.getContentsOfDirectory(at: url, calculateCounts: true)
            let folders = items.filter { $0.isDirectory }
            let nodes = folders.map { UIFolderNode(id: "\(currentPath)/\($0.name)", item: $0) }
            
            await MainActor.run {
                self.subNodes = nodes
            }
        }
    }
}

// MARK: - Folder Context Menu (NSViewRepresentable)
// SwiftUI .contextMenu fires on the outermost List row in nested DisclosureGroups,
// always capturing the root folder. This NSView-based approach ensures right-click
// targets the exact folder that was clicked.

class FolderMenuNSView: NSView {
    var onRename: (() -> Void)?
    var onNewFolder: (() -> Void)?
    var onMoveToTrash: (() -> Void)?

    // Only intercept right-click events; pass through left-click, drag, etc.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent else { return nil }
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return super.hitTest(point)
        default:
            return nil
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        let rename = NSMenuItem(title: "Rename", action: #selector(doRename), keyEquivalent: "")
        rename.target = self
        menu.addItem(rename)

        let newFolder = NSMenuItem(title: "New Folder...", action: #selector(doNewFolder), keyEquivalent: "")
        newFolder.target = self
        menu.addItem(newFolder)

        menu.addItem(.separator())

        let trash = NSMenuItem(title: "Move to Trash", action: #selector(doMoveToTrash), keyEquivalent: "")
        trash.target = self
        menu.addItem(trash)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func doRename() { onRename?() }
    @objc private func doNewFolder() { onNewFolder?() }
    @objc private func doMoveToTrash() { onMoveToTrash?() }
}

struct FolderContextMenu: NSViewRepresentable {
    var onRename: () -> Void
    var onNewFolder: () -> Void
    var onMoveToTrash: () -> Void

    func makeNSView(context: Context) -> FolderMenuNSView { FolderMenuNSView() }

    func updateNSView(_ nsView: FolderMenuNSView, context: Context) {
        nsView.onRename = onRename
        nsView.onNewFolder = onNewFolder
        nsView.onMoveToTrash = onMoveToTrash
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
        // Check for internal drag using DragState
        if DragState.shared.isValid, let source = DragState.shared.currentDragSource {
            let sourcePath = source.standardizedFileURL.path
            let targetPath = targetFolder.url.standardizedFileURL.path
            
            // Case 1: Dragging a Folder onto itself
            if sourcePath == targetPath {
                return DropProposal(operation: .forbidden)
            }
            // Case 2: Dragging a Folder into its own child (Recursive)
            // Ensure we match directory boundary by adding slash
            let sourcePathWithSlash = sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"
            if targetPath.hasPrefix(sourcePathWithSlash) {
                 return DropProposal(operation: .forbidden)
            }
            // Case 3: Dragging into parent (No-op)
            if source.deletingLastPathComponent().standardizedFileURL.path == targetPath {
                return DropProposal(operation: .forbidden)
            }
            
            // Volume Check for Internal Drag
            if let sourceVol = try? source.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject,
               let targetVol = try? targetFolder.url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject {
                
                let isDifferentVolume = (sourceVol != targetVol)
                let modifiers = NSEvent.modifierFlags
                let isCommandPressed = modifiers.contains(.command)
                let isOptionPressed = modifiers.contains(.option)
                
                if isDifferentVolume {
                    // Different volume: Default to Copy
                    if isCommandPressed { return DropProposal(operation: .move) }
                    return DropProposal(operation: .copy)
                } else {
                    // Same volume: Default to Move
                    if isOptionPressed { return DropProposal(operation: .copy) }
                    return DropProposal(operation: .move)
                }
            } else {
                 // Fallback: Path Prefix Check
                 let sourcePath = source.standardizedFileURL.path
                 let targetPath = targetFolder.url.standardizedFileURL.path
                 
                 var isDifferentVolume = true
                 if sourcePath.hasPrefix("/Users") && targetPath.hasPrefix("/Users") {
                     isDifferentVolume = false
                 } else if sourcePath.hasPrefix("/Volumes") && targetPath.hasPrefix("/Volumes") {
                     let sourceComponents = source.pathComponents
                     let targetComponents = targetFolder.url.pathComponents
                     if sourceComponents.count > 2 && targetComponents.count > 2 {
                         isDifferentVolume = (sourceComponents[2] != targetComponents[2])
                     }
                 }
                 
                 let modifiers = NSEvent.modifierFlags
                 let isCommandPressed = modifiers.contains(.command)
                 let isOptionPressed = modifiers.contains(.option)
                 
                 if isDifferentVolume {
                     if isCommandPressed { return DropProposal(operation: .move) }
                     return DropProposal(operation: .copy)
                 } else {
                     if isOptionPressed { return DropProposal(operation: .copy) }
                     return DropProposal(operation: .move)
                 }
            }
            }

        
        // External Drag or Internal File Drag (DragState might be nil or file)
        let modifiers = NSEvent.modifierFlags
        let isOptionPressed = modifiers.contains(.option)
        let isCommandPressed = modifiers.contains(.command)
        
        if isOptionPressed {
            return DropProposal(operation: .copy)
        }
        
        if isCommandPressed {
             return DropProposal(operation: .move)
        }
        
        // Default for external drag is usually Copy if different volume, but we can't easily check volume of external items synchronously here without potentially blocking.
        // However, standard macOS behavior for external file drag is usually Copy.
        // Let's default to Copy for safety if we don't know?
        // Or stick to Move as requested before?
        // Actually, Finder defaults to Copy for external drives, Move for same.
        // Without source URL, we can't know.
        // But if it's an internal file drag (which we might track via DragState if we updated it for files too), we could know.
        // For now, let's stick to Move as default if no modifiers, but maybe Copy is safer?
        // User complaint was about "Different Device" drag cursor.
        // If it's internal drag, the block above handles it.
        // If it's external drag, we might need to assume Copy?
        
        return DropProposal(operation: .copy) // Changed default to Copy for safety/standard behavior when unknown
    }
    
    func performDrop(info: DropInfo) -> Bool {
        // Clear drag source
        Task { @MainActor in
            DragState.shared.clear()
        }
        
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        
        // Capture modifiers synchronously
        let modifiers = NSEvent.modifierFlags
        let isOptionPressed = modifiers.contains(.option)
        let isCommandPressed = modifiers.contains(.command)
        
        // Process first item to determine action
        _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url else { return }
            
            // Run in background to avoid freeze
            Task.detached(priority: .userInitiated) {
                // Helper to create FileItem
                func fileItem(for url: URL) -> FileItem {
                    var isDir: ObjCBool = false
                    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    return FileItem(url: url, isDirectory: isDir.boolValue, isAvailable: exists)
                }
                
                // Get selected files from ViewModel (MainActor)
                let selectedFiles = await MainActor.run { viewModel.selectedFiles }
                
                let itemsToProcess: [FileItem]
                if selectedFiles.contains(where: { $0.url == url }) {
                    itemsToProcess = Array(selectedFiles)
                } else {
                    itemsToProcess = [fileItem(for: url)]
                }
                
                // Validate Drops (Recursive/Self)
                let targetPath = targetFolder.url.standardizedFileURL.path
                for item in itemsToProcess {
                    let sourcePath = item.url.standardizedFileURL.path
                    if sourcePath == targetPath { return } // Self
                    
                    let sourcePathWithSlash = sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"
                    if targetPath.hasPrefix(sourcePathWithSlash) { return } // Recursive
                    
                    if item.url.deletingLastPathComponent().standardizedFileURL.path == targetPath { return } // Parent
                }
                
                // Volume Check
                let sourceValues = try? url.resourceValues(forKeys: [.volumeIdentifierKey])
                let destValues = try? targetFolder.url.resourceValues(forKeys: [.volumeIdentifierKey])
                
                let sourceVol = sourceValues?.volumeIdentifier as? NSObject
                let destVol = destValues?.volumeIdentifier as? NSObject
                let isSameVolume = (sourceVol != nil && destVol != nil && sourceVol == destVol)
                
                // Determine Action
                enum DropAction {
                    case copy, move
                }
                
                let action: DropAction
                if isOptionPressed {
                    action = .copy
                } else if isSameVolume {
                    action = .move
                } else {
                    // Different volume default is Copy
                    if isCommandPressed {
                        action = .move
                    } else {
                        action = .copy
                    }
                }
                
                print("DEBUG: performDrop Action: \(action) for \(itemsToProcess.count) items")
                
                // Perform Action
                await MainActor.run {
                    switch action {
                    case .copy:
                        viewModel.requestCopyFiles(itemsToProcess, to: targetFolder.url)
                    case .move:
                        viewModel.requestMoveFiles(itemsToProcess, to: targetFolder.url)
                    }
                }
            }
        }
        return true
    }
}
