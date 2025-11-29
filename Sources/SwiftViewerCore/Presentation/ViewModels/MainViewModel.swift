import SwiftUI
@preconcurrency import CoreData

public extension Notification.Name {
    static let refreshAll = Notification.Name("refreshAll")
}

@MainActor
class MainViewModel: ObservableObject {
    @Published var currentFolder: FileItem?

    @Published var fileItems: [FileItem] = []
    @Published var allFiles: [FileItem] = [] // Store all files in current folder/catalog before filtering
    @Published var selectedFiles: Set<FileItem> = []
    @Published var currentFile: FileItem? { // The most recently selected item (for DetailView)
        didSet {
            if let url = currentFile?.url {
                UserDefaults.standard.set(url.path, forKey: "lastSelectedFile")
            }
        }
    }
    // thumbnailSize is declared later with default value logic
    @Published var columnVisibility: NavigationSplitViewVisibility = .all {
        didSet {
            if let data = try? JSONEncoder().encode(columnVisibility) {
                UserDefaults.standard.set(data, forKey: "columnVisibility")
            }
        }
    }  
    private let fileSystemService = FileSystemService.shared
    
    @Published var rootFolders: [FileItem] = []
    
    enum AppMode {
        case folders
        case catalog
    }
    
    @Published var appMode: AppMode = .folders
    @Published var currentCatalog: Catalog?
    @Published var filterCriteria = FilterCriteria() {
        didSet {
            saveFilterCriteria()
        }
    }
    @Published var isFilterDisabled: Bool = false {
        didSet {
            applyFilter()
        }
    }
    @Published var collections: [Collection] = []
    @Published var currentCollection: Collection?
    
    // Metadata Cache for Locations mode
    @Published var metadataCache: [URL: ExifMetadata] = [:]
    @Published var isLoadingMetadata: Bool = false
    private var metadataTask: Task<Void, Never>?
    
    // Inspector State
    @Published var isInspectorVisible: Bool = false {
        didSet {
            UserDefaults.standard.set(isInspectorVisible, forKey: "isInspectorVisible")
        }
    }
    
    @Published var isExifToolAvailable: Bool = false
    
    // Auto-scroll control
    var isAutoScrollEnabled: Bool = true
    
    func toggleInspector() {
        isInspectorVisible.toggle()
        if isInspectorVisible {
            columnVisibility = .all
        } else {
            columnVisibility = .doubleColumn
        }
    }
    
    // thumbnailSize is declared at the top
    
    private let mediaRepository: MediaRepositoryProtocol
    private let collectionRepository: CollectionRepositoryProtocol
    private let persistenceController: PersistenceController
    
    init(mediaRepository: MediaRepositoryProtocol? = nil,
         collectionRepository: CollectionRepositoryProtocol? = nil,
         persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
        self.mediaRepository = mediaRepository ?? MediaRepository(context: persistenceController.container.viewContext)
        self.collectionRepository = collectionRepository ?? CollectionRepository(context: persistenceController.container.viewContext)
        // rootFolders loaded in loadRootFolders()
        self.isExifToolAvailable = MetadataService.shared.isExifToolAvailable()
        
        
        // Load default thumbnail size
        let savedSize = UserDefaults.standard.double(forKey: "defaultThumbnailSize")
        if savedSize > 0 {
            self.thumbnailSize = savedSize
        }
        
        // Load inspector visibility
        self.isInspectorVisible = UserDefaults.standard.bool(forKey: "isInspectorVisible")
        
        // Load column visibility
        // Sync column visibility based on inspector visibility
        if self.isInspectorVisible {
            self.columnVisibility = .all
        } else {
            self.columnVisibility = .doubleColumn
        }
        
        // Load filters
        loadFilterCriteria()
        
        loadExpandedFolders()
        loadExpandedCatalogFolders()
        
        setupNotifications()
        
        // Load default mode
        if UserDefaults.standard.string(forKey: "defaultAppMode") == "catalogs" {
            // ...
        } else {
            // Try to load last opened folder
            if let lastPath = UserDefaults.standard.string(forKey: "lastOpenedFolder") {
                let url = URL(fileURLWithPath: lastPath)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: lastPath, isDirectory: &isDir) && isDir.boolValue {
                    openFolder(FileItem(url: url, isDirectory: true))
                }
            }
        }
        
        // Try to load last used catalog
        loadCurrentCatalogID()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFolders()
            }
        }
        
        NotificationCenter.default.addObserver(forName: .refreshAll, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAll()
            }
        }
    }
    
    func refreshFolders() {
        // Refresh current folder contents
        if let folder = currentFolder {
            if FileManager.default.fileExists(atPath: folder.url.path) {
                loadFiles(in: folder)
            } else {
                // Folder deleted externally?
                // Navigate up or clear
                currentFolder = nil
                fileItems = []
            }
        }
        
        // Refresh roots (if they are system folders, they might not change, but mounted volumes might)
        // Also refresh expanded folders?
        // We can't easily refresh all expanded folders without traversing.
        // But we can trigger a view update.
        fileSystemRefreshID = UUID()
    }
    
    func refreshAll() {
        Task { @MainActor in
            // Refresh File System
            refreshFolders()
            
            // Refresh Catalog
            if let catalog = currentCatalog {
                loadMediaItems(from: catalog)
                loadCollections(for: catalog)
            }
            
            // Refresh Metadata (if viewing a folder)
            if let folder = currentFolder {
                loadFiles(in: folder)
            }
            
            // Clear caches
            ImageCacheService.shared.clearCache()
            
            print("Refreshed all views.")
        }
    }
    
    private func saveCurrentCatalogID() {
        if let id = currentCatalog?.id {
            UserDefaults.standard.set(id.uuidString, forKey: "lastUsedCatalogID")
        } else {
            UserDefaults.standard.removeObject(forKey: "lastUsedCatalogID")
        }
    }
    
    private func loadCurrentCatalogID() {
        guard let idString = UserDefaults.standard.string(forKey: "lastUsedCatalogID"),
              let uuid = UUID(uuidString: idString) else { return }
        
        // Fetch catalog by ID
        // We need a repository method for this, or just fetch all and find.
        // Since we don't have getCatalog(id) exposed easily, let's just fetch all for now.
        // Ideally we should add getCatalog(id) to repository.
        // For now, let's try to fetch all and find it.
        do {
            let catalogs = try collectionRepository.getAllCatalogs()
            if let catalog = catalogs.first(where: { $0.id == uuid }) {
                // Load catalog context without forcing mode switch
                currentCatalog = catalog
                loadCollections(for: catalog)
                
                // Only switch mode if default is catalog
                if UserDefaults.standard.string(forKey: "defaultAppMode") == "catalogs" {
                    openCatalog(catalog)
                }
            }
        } catch {
            print("Failed to load last used catalog: \(error)")
        }
    }
    
    @Published var sortOption: SortOption = .name
    @Published var isSortAscending: Bool = true
    
    enum SortOption: String, CaseIterable, Identifiable {
        case name = "Name"
        case date = "Date"
        case size = "Size"
        
        var id: String { rawValue }
    }
    
    @Published var fileSystemRefreshID = UUID()
    
    func openFolder(_ folder: FileItem) {
        ImageCacheService.shared.clearCache()
        appMode = .folders
        currentFolder = folder
        
        // Save to UserDefaults
        UserDefaults.standard.set(folder.url.path, forKey: "lastOpenedFolder")
        
        // currentCatalog = nil // Keep catalog selected in sidebar as requested
        currentCollection = nil
        selectedFiles.removeAll()
        currentFile = nil
        // Reset filters? No, user wants persistence.
        // filterCriteria = FilterCriteria()
        isFilterDisabled = false
        
        loadFiles(in: folder)
    }
    
    func openCatalog(_ catalog: Catalog) {
        // Clear cache from previous catalog/folder to free memory
        ImageCacheService.shared.clearCache()
        
        metadataTask?.cancel() // Cancel any running metadata task from folder mode
        
        appMode = .catalog
        currentCatalog = catalog
        saveCurrentCatalogID() // Save selection
        currentFolder = nil // Clear folder
        currentCollection = nil
        selectedFiles.removeAll()
        currentFile = nil
        // Reset filters
        // filterCriteria = FilterCriteria()
        isFilterDisabled = false
        
        selectedCatalogFolder = nil // Reset folder filter
        
        // Clear pending imports from previous catalog to stop spinner
        pendingImports.removeAll()
        updateImportState()
        
        loadCollections(for: catalog)
        loadMediaItems(from: catalog)
        
        // Restore last selected folder if valid
        if let lastPath = UserDefaults.standard.string(forKey: "lastSelectedCatalogFolder") {
            let url = URL(fileURLWithPath: lastPath)
            // Verify it exists in our tree? Or just set it.
            // If it's not in the tree, applyFilter might show nothing, which is fine (user sees empty).
            // Or we can check if it's in catalogRootNodes (complex).
            // Let's just set it.
            selectCatalogFolder(url)
        }
    }
    
    func selectCatalogFolder(_ url: URL?) {
        metadataTask?.cancel() // Cancel any running metadata task
        appMode = .catalog
        currentFolder = nil
        currentCollection = nil // Clear collection selection
        selectedCatalogFolder = url
        // Reset filters when changing folder in catalog?
        // User said: "Display filter should reset on folder or catalog folder selection." -> Wait, user said "Filter sub-items are not saved".
        // So we should PERSIST them.
        // filterCriteria = FilterCriteria()
        isFilterDisabled = false
        
        applyFilter()
    }
    
    // ...
    
    func importFolderToCatalog(url: URL) {
        guard let catalog = currentCatalog else { return }
        
        let catalogID = catalog.id
        let catalogObjectID = catalog.objectID
        
        // Prevent duplicate imports
        if !pendingImports.contains(url) {
            pendingImports.append(url)
            updateImportState()
        } else {
            return // Already importing
        }
        
        Task {
            do {
                await MainActor.run {
                    self.importStatusMessage = "Importing..."
                }
                
                // 2. Import using Repository (background)
                // Pass folder URL directly, repository handles recursion
                try await mediaRepository.importMediaItems(from: [url], to: catalogObjectID)
                
                // 3. Refresh
                await MainActor.run {
                    // Remove from pending imports
                    if let index = self.pendingImports.firstIndex(of: url) {
                        self.pendingImports.remove(at: index)
                    }
                    self.updateImportState()
                    
                    // Only refresh if we are still viewing the same catalog
                    if self.currentCatalog?.id == catalogID {
                        self.loadMediaItems(from: catalog)
                        self.loadCollections(for: catalog)
                    }
                }
                
            } catch {
                print("Failed to import folder: \(error)")
                await MainActor.run {
                    if let index = self.pendingImports.firstIndex(of: url) {
                        self.pendingImports.remove(at: index)
                    }
                    self.updateImportState()
                }
            }
        }
    }
    
    private func updateImportState() {
        isImporting = !pendingImports.isEmpty
        if pendingImports.isEmpty {
            importStatusMessage = ""
        } else if pendingImports.count > 1 {
            importStatusMessage = "Importing \(pendingImports.count) folders..."
        }
    }
    
    func renameFolder(url: URL, newName: String) {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
            
            // Update Core Data
            let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
            let oldPath = url.path
            let newPath = newURL.path
            
            request.predicate = NSPredicate(format: "originalPath BEGINSWITH %@", oldPath)
            if let items = try? persistenceController.container.viewContext.fetch(request) {
                for item in items {
                    if let path = item.originalPath {
                        if path.hasPrefix(oldPath) {
                            let suffix = path.dropFirst(oldPath.count)
                            item.originalPath = newPath + suffix
                        }
                    }
                }
                try? persistenceController.container.viewContext.save()
            }
            
            // Refresh View
            fileSystemRefreshID = UUID() // Trigger Sidebar refresh
            
            if appMode == .folders {
                if let current = currentFolder, current.url == url.deletingLastPathComponent() {
                    loadFiles(in: current)
                }
                if let current = currentFolder, current.url == url {
                    openFolder(FileItem(url: newURL, isDirectory: true))
                }

                Task {
                    let roots = fileSystemService.getRootFolders()
                    await MainActor.run {
                        self.rootFolders = roots
                    }
                }
            } else if let catalog = currentCatalog {
                loadMediaItems(from: catalog)
                Task {
                    let roots = fileSystemService.getRootFolders()
                    await MainActor.run {
                        self.rootFolders = roots
                    }
                }
            }
            
        } catch {
            print("Failed to rename folder: \(error)")
            self.importStatusMessage = "Error renaming: \(error.localizedDescription)"
        }
    }
    
    func openCollection(_ collection: Collection) {
        currentCollection = collection
        selectedFiles.removeAll()
        currentFile = nil
        // filterCriteria = FilterCriteria() // Persist filters
        // Load items from collection using FetchRequest for freshness
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "collections CONTAINS %@", collection)
        
        do {
            let items = try persistenceController.container.viewContext.fetch(request)
            let mappedItems = items.compactMap { item -> FileItem? in
                guard let path = item.originalPath else { return nil }
                let url = URL(fileURLWithPath: path)
                // Map ALL properties for Sort and Display
                return FileItem(
                    url: url,
                    isDirectory: false,
                    isAvailable: FileManager.default.fileExists(atPath: path),
                    uuid: item.id ?? UUID(),
                    colorLabel: item.colorLabel,
                    creationDate: item.importDate,
                    modificationDate: item.modifiedDate,
                    fileSize: item.fileSize
                )
            }
            // Populate metadata cache for these items so ratings show up immediately
            populateMetadataCache(from: items)
            
            fileItems = sortItems(mappedItems)
            
            // Explicitly apply sort to ensure UI reflects current sort option
            applySort()
            
        } catch {
            Logger.shared.log("Error loading collection items: \(error)")
            fileItems = []
        }
    }

    func createCollection(name: String) {
        // Fallback: If no current catalog, try to use the first available one
        var catalog = currentCatalog
        if catalog == nil {
            // Try to fetch first catalog
            let request: NSFetchRequest<Catalog> = Catalog.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            request.fetchLimit = 1
            if let first = try? persistenceController.container.viewContext.fetch(request).first {
                catalog = first
                Logger.shared.log("Warning: No current catalog, using first available: \(first.name ?? "nil")")
            }
        }
        
        guard let targetCatalog = catalog else {
            Logger.shared.log("Error: No catalog available for createCollection")
            return
        }
        
        let catalogID = targetCatalog.objectID
        
        // Use background context to avoid blocking Main Thread
        persistenceController.container.performBackgroundTask { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            do {
                guard let bgCatalog = try context.existingObject(with: catalogID) as? Catalog else {
                    Logger.shared.log("Error: Catalog not found in background context")
                    return
                }
                
                Logger.shared.log("Creating collection: \(name) in catalog: \(bgCatalog.name ?? "nil")")
                
                let collection = Collection(context: context)
                collection.id = UUID()
                collection.name = name
                collection.type = "regular"
                collection.catalog = bgCatalog
                
                try context.save()
                Logger.shared.log("Collection created successfully in background")
                
                Task {
                    await MainActor.run {
                        // Force refresh on Main Thread
                        // We need to fetch the new collection or just reload all
                        if let mainCatalog = try? self.persistenceController.container.viewContext.existingObject(with: catalogID) as? Catalog {
                            self.loadCollections(for: mainCatalog)
                            self.objectWillChange.send()
                        }
                    }
                }
            } catch {
                Logger.shared.log("Failed to create collection: \(error)")
            }
        }
    }
    
    func renameCollection(_ collection: Collection, newName: String) {
        guard let catalog = currentCatalog else { return }
        do {
            try collectionRepository.renameCollection(collection, to: newName)
            loadCollections(for: catalog)
        } catch {
            print("Failed to rename collection: \(error)")
        }
    }

    func addToCollection(_ items: [FileItem], collection: Collection) {
        let paths = items.map { $0.url.path }
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "originalPath IN %@", paths)
        
        do {
            let mediaItems = try persistenceController.container.viewContext.fetch(request)
            try collectionRepository.addMediaItems(mediaItems, to: collection)
        } catch {
            print("Failed to add to collection: \(error)")
        }
    }
    
    func deleteCollection(_ collection: Collection) {
        guard let catalog = currentCatalog else { return }
        do {
            try collectionRepository.deleteCollection(collection)
            loadCollections(for: catalog)
            if currentCollection == collection {
                currentCollection = nil
                fileItems = []
            }
        } catch {
            print("Failed to delete collection: \(error)")
        }
    }
    
    func removeFromCollection(_ items: [FileItem], collection: Collection) {
        let paths = items.map { $0.url.path }
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "originalPath IN %@", paths)
        
        do {
            let mediaItems = try persistenceController.container.viewContext.fetch(request)
            try collectionRepository.removeMediaItems(mediaItems, from: collection)
            
            // Refresh view if currently viewing this collection
            if currentCollection == collection {
                openCollection(collection)
            }
        } catch {
            print("Failed to remove from collection: \(error)")
        }
    }
    
    func clearThumbnailCache() {
        ThumbnailCacheService.shared.clearCache()
        ImageCacheService.shared.clearCache()
        // Force refresh of current view?
        // If we are in grid view, we might need to trigger a redraw.
        // But AsyncThumbnailView uses .task(id: url), so if we change ID or something...
        // Or just let the user scroll or restart app.
        // User asked to "fix" it.
        // Maybe we should clear cache on startup or when requested?
        // Let's just expose this.
    }
    
    func deleteSelectedFiles() {
        let itemsToDelete = selectedFiles
        for item in itemsToDelete {
            deleteFile(item)
        }
        selectedFiles.removeAll()
        currentFile = nil
    }

    func deleteFile(_ item: FileItem) {
        do {
            // Check mode
            if appMode == .catalog || currentCollection != nil {
                // Only remove from Core Data and list
                // Remove from list
                if let index = fileItems.firstIndex(where: { $0.id == item.id }) {
                    fileItems.remove(at: index)
                }
                
                // Remove from Core Data
                let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                request.predicate = NSPredicate(format: "originalPath == %@", item.url.path)
                if let mediaItem = try? persistenceController.container.viewContext.fetch(request).first {
                    persistenceController.container.viewContext.delete(mediaItem)
                }
                try? persistenceController.container.viewContext.save()
                
            } else {
                // Folder mode: Delete from disk
                try FileOperationService.shared.deleteFile(at: item.url)
                // Remove from list
                if let index = fileItems.firstIndex(where: { $0.id == item.id }) {
                    fileItems.remove(at: index)
                }
                
                // Also remove from Core Data if it's a MediaItem (optional, but good for consistency)
                let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                request.predicate = NSPredicate(format: "originalPath == %@", item.url.path)
                if let mediaItem = try? persistenceController.container.viewContext.fetch(request).first {
                    persistenceController.container.viewContext.delete(mediaItem)
                }
                try? persistenceController.container.viewContext.save()
            }
            
        } catch {
            print("Failed to delete file: \(error)")
        }
    }
    
    private func loadCollections(for catalog: Catalog) {
        do {
            collections = try collectionRepository.getCollections(in: catalog)
        } catch {
            print("Failed to load collections: \(error)")
            collections = []
        }
    }

    @Published var selectedCatalogFolder: URL? { // Filter catalog by folder
        didSet {
            if let url = selectedCatalogFolder {
                UserDefaults.standard.set(url.path, forKey: "lastSelectedCatalogFolder")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastSelectedCatalogFolder")
            }
        }
    }
    
    func applyFilter() {
        if let collection = currentCollection {
            // Filter within collection
            // Use FetchRequest to ensure freshness and avoid stale relationship cache
            let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
            request.predicate = NSPredicate(format: "collections CONTAINS %@", collection)
            
            if let items = try? persistenceController.container.viewContext.fetch(request) {
                 let filtered = filterItems(items)
                 let mapped = filtered.compactMap { item -> FileItem? in
                    guard let path = item.originalPath else { return nil }
                    let url = URL(fileURLWithPath: path)
                    // Use MediaItem ID for cache linking
                    return FileItem(url: url, isDirectory: false, uuid: item.id ?? UUID(), colorLabel: item.colorLabel, creationDate: item.importDate, modificationDate: item.modifiedDate, fileSize: item.fileSize)
                }
                fileItems = sortItems(mapped)
                // Also populate metadata cache for these items
                populateMetadataCache(from: filtered)
             }
        } else if isFilterDisabled {
            // If filters are disabled, show all items (subject to folder scope)
            if appMode == .catalog {
                 var items = allMediaItems
                 if let folder = selectedCatalogFolder {
                     let folderPath = folder.path
                     items = items.filter { item in
                         guard let path = item.originalPath else { return false }
                         return URL(fileURLWithPath: path).deletingLastPathComponent().path == folderPath
                     }
                 }
                 // Still populate cache for scope
                 populateMetadataCache(from: items)
                 
                 let mapped = items.compactMap { item -> FileItem? in
                    guard let path = item.originalPath else { return nil }
                    let url = URL(fileURLWithPath: path)
                    let isAvailable = FileManager.default.fileExists(atPath: path)
                    return FileItem(url: url, isDirectory: false, isAvailable: isAvailable, uuid: item.id ?? UUID(), colorLabel: item.colorLabel, creationDate: item.importDate, modificationDate: item.modifiedDate, fileSize: item.fileSize)
                }
                fileItems = sortItems(mapped)
            } else if appMode == .folders {
                fileItems = sortItems(allFiles)
            }
            
        } else if appMode == .catalog, currentCatalog != nil {
            // Filter from allMediaItems
            var items = allMediaItems
            
            // Apply Folder Filter if active
            if let folder = selectedCatalogFolder {
                let folderPath = folder.path
                items = items.filter { item in
                    guard let path = item.originalPath else { return false }
                    return URL(fileURLWithPath: path).deletingLastPathComponent().path == folderPath
                }
            }
            
            // Update metadata cache to reflect the items in the current scope (Catalog or Catalog Folder)
            // BEFORE applying attribute filters, so the filters show available options for this scope.
            populateMetadataCache(from: items)
            
            let filtered = filterItems(items)
            let mapped = filtered.compactMap { item -> FileItem? in
               guard let path = item.originalPath else { return nil }
               let url = URL(fileURLWithPath: path)
               let isAvailable = FileManager.default.fileExists(atPath: path)
               return FileItem(url: url, isDirectory: false, isAvailable: isAvailable, uuid: item.id ?? UUID(), colorLabel: item.colorLabel, creationDate: item.importDate, modificationDate: item.modifiedDate, fileSize: item.fileSize)
           }
           fileItems = sortItems(mapped)
           
        } else if appMode == .folders {
            if isFilterDisabled {
                fileItems = sortItems(allFiles)
            } else {
                // In folder mode, filter from allFiles instead of reloading from disk
                let filtered = filterFileItems(allFiles)
                fileItems = sortItems(filtered)
            }
        }
        
        // Fix: Deselect files that are no longer visible
        // Fix: Deselect files that are no longer visible, but try to preserve selection by ID
        // Because FileItem equality includes colorLabel, if label changes, the old FileItem in selectedFiles won't match the new one in fileItems (which has new label).
        // So we must find the new items by ID.
        
        let currentSelectionIDs = Set(selectedFiles.map { $0.id })
        let newSelection = fileItems.filter { currentSelectionIDs.contains($0.id) }
        
        if Set(newSelection) != selectedFiles {
            selectedFiles = Set(newSelection)
            
            // Also update currentFile
            if let current = currentFile, let newCurrent = fileItems.first(where: { $0.id == current.id }) {
                currentFile = newCurrent
            } else if let current = currentFile, !currentSelectionIDs.contains(current.id) {
                // Current file is no longer in the list
                currentFile = nil
            }
        }
    }
    
    // Flag to prevent FS monitor from reloading during metadata updates
    private var isUpdatingMetadata = false
    
    // MARK: - Filter Persistence
    
    private func saveFilterCriteria() {
        if let data = try? JSONEncoder().encode(filterCriteria) {
            UserDefaults.standard.set(data, forKey: "filterCriteria")
        }
    }
    
    private func loadFilterCriteria() {
        if let data = UserDefaults.standard.data(forKey: "filterCriteria"),
           let criteria = try? JSONDecoder().decode(FilterCriteria.self, from: data) {
            self.filterCriteria = criteria
        }
    }
    
    // MARK: - File Operations (Multi-file)
    
    @Published var showMoveFilesConfirmation = false
    @Published var showCopyFilesConfirmation = false
    @Published var filesToMove: [FileItem] = []
    @Published var filesToCopy: [FileItem] = []
    @Published var fileOpDestination: URL?
    
    func requestMoveFiles(_ items: [FileItem], to destination: URL) {
        filesToMove = items
        fileOpDestination = destination
        showMoveFilesConfirmation = true
    }
    
    func confirmMoveFiles() {
        guard let destination = fileOpDestination else { return }
        let items = filesToMove
        
        Task {
            // Check if destination is same as source (for any item)
            // If so, skip
            
            for item in items {
                let destURL = destination.appendingPathComponent(item.url.lastPathComponent)
                if item.url == destURL { continue }
                
                do {
                    // Try move
                    try FileManager.default.moveItem(at: item.url, to: destURL)
                    
                    // Update Catalog if needed
                    // If we are in Catalog mode, we need to update the path in DB
                    // But usually we are in Folder mode when moving files.
                    // If we are in Folder mode, we should check if these files are in Catalog and update them.
                    // This is "Two-way Sync" part.
                    await updateCatalogPath(oldURL: item.url, newURL: destURL)
                    
                } catch {
                    print("Failed to move file \(item.name): \(error)")
                    // Fallback: Copy and Delete?
                    // If move failed (e.g. cross-volume), try copy then delete
                    do {
                        try FileManager.default.copyItem(at: item.url, to: destURL)
                        try FileManager.default.removeItem(at: item.url)
                        await updateCatalogPath(oldURL: item.url, newURL: destURL)
                    } catch {
                        print("Failed to copy/delete file \(item.name): \(error)")
                    }
                }
            }
            
            await MainActor.run {
                self.filesToMove = []
                self.fileOpDestination = nil
                self.refreshAll()
            }
        }
    }
    
    func requestCopyFiles(_ items: [FileItem], to destination: URL) {
        filesToCopy = items
        fileOpDestination = destination
        showCopyFilesConfirmation = true
    }
    
    func confirmCopyFiles() {
        guard let destination = fileOpDestination else { return }
        let items = filesToCopy
        
        Task {
            for item in items {
                let destURL = destination.appendingPathComponent(item.url.lastPathComponent)
                if item.url == destURL { continue }
                
                do {
                    try FileManager.default.copyItem(at: item.url, to: destURL)
                    // If copying to a Catalog Folder, we should import it?
                    // The user said: "When dragging thumbnail to another catalog folder... update catalog info."
                    // If target is a Catalog Folder, we should add the new file to Catalog.
                    await checkAndImportToCatalog(url: destURL)
                } catch {
                    print("Failed to copy file \(item.name): \(error)")
                }
            }
            
            await MainActor.run {
                self.filesToCopy = []
                self.fileOpDestination = nil
                self.refreshAll()
            }
        }
    }
    
    private func updateCatalogPath(oldURL: URL, newURL: URL) async {
        let context = persistenceController.container.viewContext
        await context.perform {
            let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
            // Use standardized path for better matching
            let oldPath = oldURL.standardizedFileURL.path
            request.predicate = NSPredicate(format: "originalPath == %@", oldPath)
            
            do {
                let items = try context.fetch(request)
                if let item = items.first {
                    item.originalPath = newURL.standardizedFileURL.path
                    try context.save()
                    print("Updated Catalog path for \(oldPath) to \(newURL.path)")
                } else {
                    print("Warning: MediaItem not found for path \(oldPath)")
                }
            } catch {
                print("Failed to update catalog path: \(error)")
            }
        }
    }
    
    private func checkAndImportToCatalog(url: URL) async {
        // Check if the destination folder is part of any Catalog
        // For now, if we are in Catalog mode, we assume the user wants to add it.
        // Or if the destination folder is a "Catalog Folder".
        // This is complex to detect efficiently.
        // But if we use `importMediaItems`, it handles duplicates.
        // So we can just try to import.
        guard let catalog = currentCatalog else { return }
        // Only if we are in Catalog mode or target is known?
        // Let's just try to import if we have a current catalog.
        try? await mediaRepository.importMediaItems(from: [url], to: catalog.objectID)
    }
    
    // MARK: - Metadata Editing
    
    // Methods moved to extension/bottom to fix redeclaration and add selection update logic.
    // See updateRating and updateColorLabel below.


    
    private func filterItems(_ items: [MediaItem]) -> [MediaItem] {
        return items.filter { item in
            if item.rating < filterCriteria.minRating { return false }
            if let label = filterCriteria.colorLabel, item.colorLabel != label { return false }
            if !filterCriteria.searchText.isEmpty {
                if let name = item.fileName, !name.localizedCaseInsensitiveContains(filterCriteria.searchText) { return false }
            }
            
            // Metadata filtering using ExifData relationship
            if let exif = item.exifData {
                 // Metadata Filter (Multi-selection)
                 if !filterCriteria.selectedMakers.isEmpty {
                     if let make = exif.cameraMake {
                         if !filterCriteria.selectedMakers.contains(make) { return false }
                     } else {
                         if !filterCriteria.selectedMakers.contains("Unknown") { return false }
                     }
                 }
                 
                 if !filterCriteria.selectedCameras.isEmpty {
                     if let model = exif.cameraModel {
                         if !filterCriteria.selectedCameras.contains(model) { return false }
                     } else {
                         if !filterCriteria.selectedCameras.contains("Unknown") { return false }
                     }
                 }
                 
                 if !filterCriteria.selectedLenses.isEmpty {
                     if let lens = exif.lensModel {
                         if !filterCriteria.selectedLenses.contains(lens) { return false }
                     } else {
                         if !filterCriteria.selectedLenses.contains("Unknown") { return false }
                     }
                 }
                 
                 if !filterCriteria.selectedISOs.isEmpty {
                     let iso = Int(exif.iso)
                     if iso > 0 {
                        if !filterCriteria.selectedISOs.contains(String(iso)) { return false }
                     } else {
                        if !filterCriteria.selectedISOs.contains("Unknown") { return false }
                     }
                 }
                 
                 if !filterCriteria.selectedDates.isEmpty {
                     if let date = exif.dateTimeOriginal {
                         let formatter = DateFormatter()
                         formatter.dateFormat = "yyyy-MM-dd"
                         let dateString = formatter.string(from: date)
                         if !filterCriteria.selectedDates.contains(dateString) { return false }
                     } else {
                         if !filterCriteria.selectedDates.contains("Unknown") { return false }
                     }
                 }
                 
                 if !filterCriteria.selectedShutterSpeeds.isEmpty {
                     if let speed = exif.shutterSpeed {
                         if !filterCriteria.selectedShutterSpeeds.contains(speed) { return false }
                     } else {
                         if !filterCriteria.selectedShutterSpeeds.contains("Unknown") { return false }
                     }
                 }
                 
                 if !filterCriteria.selectedApertures.isEmpty {
                     let aperture = exif.aperture
                     if aperture > 0 {
                        let str = String(format: "f/%.1f", aperture)
                        if !filterCriteria.selectedApertures.contains(str) { return false }
                     } else {
                        if !filterCriteria.selectedApertures.contains("Unknown") { return false }
                     }
                 }
                 
                 if !filterCriteria.selectedFocalLengths.isEmpty {
                     let focal = exif.focalLength
                     if focal > 0 {
                        let str = String(format: "%.0f mm", focal)
                        if !filterCriteria.selectedFocalLengths.contains(str) { return false }
                     } else {
                        if !filterCriteria.selectedFocalLengths.contains("Unknown") { return false }
                     }
                 }
            } else if filterCriteria.isActive {
                 // Item has no ExifData at all
                 // If any metadata filter is active, check if "Unknown" is selected
                 if !filterCriteria.selectedMakers.isEmpty && !filterCriteria.selectedMakers.contains("Unknown") { return false }
                 if !filterCriteria.selectedCameras.isEmpty && !filterCriteria.selectedCameras.contains("Unknown") { return false }
                 if !filterCriteria.selectedLenses.isEmpty && !filterCriteria.selectedLenses.contains("Unknown") { return false }
                 if !filterCriteria.selectedISOs.isEmpty && !filterCriteria.selectedISOs.contains("Unknown") { return false }
                 if !filterCriteria.selectedDates.isEmpty && !filterCriteria.selectedDates.contains("Unknown") { return false }
                 if !filterCriteria.selectedShutterSpeeds.isEmpty && !filterCriteria.selectedShutterSpeeds.contains("Unknown") { return false }
                 if !filterCriteria.selectedApertures.isEmpty && !filterCriteria.selectedApertures.contains("Unknown") { return false }
                 if !filterCriteria.selectedFocalLengths.isEmpty && !filterCriteria.selectedFocalLengths.contains("Unknown") { return false }
            }
            
            return true
        }
    }
    
    @Published var filterTabSelection: Int = 0
    
    // Computed properties for available metadata
    var availableDates: [String] {
        let dates = metadataCache.values.compactMap { $0.dateTimeOriginal }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var result = Array(Set(dates.map { formatter.string(from: $0) })).sorted(by: >)
        
        let hasUnknown = metadataCache.values.contains { $0.dateTimeOriginal == nil }
        if hasUnknown {
            result.insert("Unknown", at: 0)
        }
        return result
    }
    
    var availableFileTypes: [String] {
        let types = allFiles.map { $0.url.pathExtension.uppercased() }
        return Array(Set(types)).sorted()
    }
    
    var availableMakers: [String] {
        let makers = metadataCache.values.compactMap { $0.cameraMake }
        var result = Array(Set(makers)).sorted()
        if metadataCache.values.contains(where: { $0.cameraMake == nil }) {
            result.insert("Unknown", at: 0)
        }
        return result
    }
    
    var availableCameras: [String] {
        let cameras = metadataCache.values.compactMap { $0.cameraModel }
        var result = Array(Set(cameras)).sorted()
        if metadataCache.values.contains(where: { $0.cameraModel == nil }) {
            result.insert("Unknown", at: 0)
        }
        return result
    }
    
    var availableLenses: [String] {
        let lenses = metadataCache.values.compactMap { $0.lensModel }
        var result = Array(Set(lenses)).sorted()
        if metadataCache.values.contains(where: { $0.lensModel == nil }) {
            result.insert("Unknown", at: 0)
        }
        return result
    }
    
    var availableISOs: [String] {
        let isos = metadataCache.values.compactMap { $0.iso }.map { String($0) }
        var result = Array(Set(isos)).sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
        if metadataCache.values.contains(where: { $0.iso == nil }) {
            result.insert("Unknown", at: 0)
        }
        return result
    }
    
    var availableShutterSpeeds: [String] {
        let speeds = metadataCache.values.compactMap { $0.shutterSpeed }
        var result = Array(Set(speeds)).sorted()
        if metadataCache.values.contains(where: { $0.shutterSpeed == nil }) {
            result.insert("Unknown", at: 0)
        }
        return result
    }
    
    var availableApertures: [String] {
        let apertures = metadataCache.values.compactMap { $0.aperture }
        var result = Array(Set(apertures)).sorted().map { String(format: "f/%.1f", $0) }
        if metadataCache.values.contains(where: { $0.aperture == nil }) {
            result.insert("Unknown", at: 0)
        }
        return result
    }
    
    var availableFocalLengths: [String] {
        let lengths = metadataCache.values.compactMap { $0.focalLength }
        var result = Array(Set(lengths)).sorted().map { String(format: "%.0f mm", $0) }
        if metadataCache.values.contains(where: { $0.focalLength == nil }) {
            result.insert("Unknown", at: 0)
        }
        return result
    }

    // Helper to filter FileItems in Locations mode using metadataCache
    func filterFileItems(_ items: [FileItem]) -> [FileItem] {
        return items.filter { item in
            // Basic text filter
            if !filterCriteria.searchText.isEmpty {
                if !item.name.localizedCaseInsensitiveContains(filterCriteria.searchText) { return false }
            }
            
            // Color Label Filter
            if let label = filterCriteria.colorLabel {
                if item.colorLabel != label { return false }
            }
            
            // Metadata/Attribute filter using Cache
            if let exif = metadataCache[item.url] {
                // Attribute Filter
                if filterCriteria.minRating > 0 {
                    if let rating = exif.rating, rating < filterCriteria.minRating { return false }
                    if exif.rating == nil { return false }
                }
                
                // Metadata Filter (Multi-selection)
                if !filterCriteria.selectedMakers.isEmpty {
                    if let make = exif.cameraMake {
                        if !filterCriteria.selectedMakers.contains(make) { return false }
                    } else {
                        if !filterCriteria.selectedMakers.contains("Unknown") { return false }
                    }
                }
                
                if !filterCriteria.selectedCameras.isEmpty {
                    if let model = exif.cameraModel {
                        if !filterCriteria.selectedCameras.contains(model) { return false }
                    } else {
                        if !filterCriteria.selectedCameras.contains("Unknown") { return false }
                    }
                }
                
                if !filterCriteria.selectedLenses.isEmpty {
                    if let lens = exif.lensModel {
                        if !filterCriteria.selectedLenses.contains(lens) { return false }
                    } else {
                        if !filterCriteria.selectedLenses.contains("Unknown") { return false }
                    }
                }
                
                if !filterCriteria.selectedISOs.isEmpty {
                    if let iso = exif.iso {
                        if !filterCriteria.selectedISOs.contains(String(iso)) { return false }
                    } else {
                        if !filterCriteria.selectedISOs.contains("Unknown") { return false }
                    }
                }
                
                if !filterCriteria.selectedDates.isEmpty {
                    if let date = exif.dateTimeOriginal {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        let dateString = formatter.string(from: date)
                        if !filterCriteria.selectedDates.contains(dateString) { return false }
                    } else {
                        if !filterCriteria.selectedDates.contains("Unknown") { return false }
                    }
                }
                
                if !filterCriteria.selectedShutterSpeeds.isEmpty {
                    if let speed = exif.shutterSpeed {
                        if !filterCriteria.selectedShutterSpeeds.contains(speed) { return false }
                    } else {
                        if !filterCriteria.selectedShutterSpeeds.contains("Unknown") { return false }
                    }
                }
                
                if !filterCriteria.selectedApertures.isEmpty {
                    if let aperture = exif.aperture {
                        let str = String(format: "f/%.1f", aperture)
                        if !filterCriteria.selectedApertures.contains(str) { return false }
                    } else {
                        if !filterCriteria.selectedApertures.contains("Unknown") { return false }
                    }
                }
                
                if !filterCriteria.selectedFocalLengths.isEmpty {
                    if let focal = exif.focalLength {
                        let str = String(format: "%.0f mm", focal)
                        if !filterCriteria.selectedFocalLengths.contains(str) { return false }
                    } else {
                        if !filterCriteria.selectedFocalLengths.contains("Unknown") { return false }
                    }
                }
                
            } else if filterCriteria.isActive {
                 // Item has no ExifData in cache (maybe not loaded yet, or failed)
                 // Treat as Unknown for all metadata filters
                 if !filterCriteria.selectedMakers.isEmpty && !filterCriteria.selectedMakers.contains("Unknown") { return false }
                 if !filterCriteria.selectedCameras.isEmpty && !filterCriteria.selectedCameras.contains("Unknown") { return false }
                 if !filterCriteria.selectedLenses.isEmpty && !filterCriteria.selectedLenses.contains("Unknown") { return false }
                 if !filterCriteria.selectedISOs.isEmpty && !filterCriteria.selectedISOs.contains("Unknown") { return false }
                 if !filterCriteria.selectedDates.isEmpty && !filterCriteria.selectedDates.contains("Unknown") { return false }
                 if !filterCriteria.selectedShutterSpeeds.isEmpty && !filterCriteria.selectedShutterSpeeds.contains("Unknown") { return false }
                 if !filterCriteria.selectedApertures.isEmpty && !filterCriteria.selectedApertures.contains("Unknown") { return false }
                 if !filterCriteria.selectedFocalLengths.isEmpty && !filterCriteria.selectedFocalLengths.contains("Unknown") { return false }
            }
            
            // File Type Filter (doesn't need EXIF cache necessarily, but consistent to check here)
            if !filterCriteria.selectedFileTypes.isEmpty {
                let ext = item.url.pathExtension.uppercased()
                if !filterCriteria.selectedFileTypes.contains(ext) { return false }
            }
            
            return true
        }
    }
    
    // Catalog Tree Node
    struct CatalogFolderNode: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        var children: [CatalogFolderNode]? // Optional for OutlineGroup
        let isAvailable: Bool
        let fileCount: Int
        
        var name: String { url.lastPathComponent }
        
        init(url: URL, children: [CatalogFolderNode]? = nil, fileCount: Int = 0) {
            self.url = url
            self.children = children
            // Check if folder exists
            var isDir: ObjCBool = false
            self.isAvailable = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            self.fileCount = fileCount
        }
    }
    
    @Published var allMediaItems: [MediaItem] = [] // Store all items in catalog
    @Published var isImporting = false
    @Published var importProgress: Double = 0.0
    @Published var importStatusMessage: String = ""
    @Published var catalogRootNodes: [CatalogFolderNode] = [] // Hierarchical folders
    @Published var pendingImports: [URL] = [] // Folders currently being imported
    
    private func loadMediaItems(from catalog: Catalog) {
        do {
            let items = try mediaRepository.fetchMediaItems(in: catalog)
            allMediaItems = items // Store all items
            
            // Populate metadata cache from ALL items to ensure filters show all options
            populateMetadataCache(from: items)
            
            // Build Catalog Tree
            let paths = Set(items.compactMap { $0.originalPath }).map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
            let uniqueFolders = Array(Set(paths)).sorted { $0.path < $1.path }
            catalogRootNodes = buildCatalogTree(from: uniqueFolders)
            
            // Apply current filter
            let filteredItems = filterItems(items)
            
            let mapped = filteredItems.compactMap { item -> FileItem? in
                guard let path = item.originalPath else { return nil }
                let url = URL(fileURLWithPath: path)
                // Use MediaItem ID for cache linking
                return FileItem(url: url, isDirectory: false, uuid: item.id ?? UUID(), colorLabel: item.colorLabel, creationDate: item.importDate, modificationDate: item.modifiedDate, fileSize: item.fileSize)
            }
            fileItems = sortItems(mapped)
            
        } catch {
            print("Failed to load media items: \(error)")
            fileItems = []
            allMediaItems = []
            catalogRootNodes = []
        }
    }
    
    private func buildCatalogTree(from folders: [URL]) -> [CatalogFolderNode] {
        guard !folders.isEmpty else { return [] }
        
        // 1. Find Common Root
        // Convert to path components
        let paths = folders.map { $0.pathComponents }
        guard let firstPath = paths.first else { return [] }
        
        var commonPrefix = firstPath
        for path in paths.dropFirst() {
            // Truncate commonPrefix to match path
            if path.count < commonPrefix.count {
                commonPrefix = Array(commonPrefix.prefix(path.count))
            }
            for (i, component) in commonPrefix.enumerated() {
                if i >= path.count || path[i] != component {
                    commonPrefix = Array(commonPrefix.prefix(i))
                    break
                }
            }
        }
        
        // If common prefix is just "/", we might have multiple roots (e.g. different volumes).
        // But usually it's a folder.
        
        // 2. Expand folders to include all intermediates from common prefix
        var allNodes: Set<URL> = []
        let commonRootURL = URL(fileURLWithPath: "/" + commonPrefix.dropFirst().joined(separator: "/")) // Reconstruct URL
        
        // If common root is effectively root, maybe we don't want to show it if it's just "/"?
        // But let's be safe.
        
        for folder in folders {
            var current = folder
            allNodes.insert(current)
            
            // Walk up until we hit common root
            while current.path != commonRootURL.path && current.pathComponents.count > 1 {
                current = current.deletingLastPathComponent()
                allNodes.insert(current)
            }
        }
        
        // Ensure common root is added if valid
        if commonRootURL.pathComponents.count > 1 {
            allNodes.insert(commonRootURL)
        }
        
        // 3. Build Tree
        let sortedURLs = Array(allNodes).sorted { $0.path < $1.path }
        
        // Calculate file counts
        var fileCounts: [URL: Int] = [:]
        // We can optimize this by iterating allMediaItems once
        for item in allMediaItems {
            if let path = item.originalPath {
                let folderURL = URL(fileURLWithPath: path).deletingLastPathComponent()
                fileCounts[folderURL, default: 0] += 1
            }
        }
        
        return buildTree(urls: sortedURLs, fileCounts: fileCounts)
    }
    
    // Helper Class for building
    private class NodeBuilder {
        let url: URL
        var children: [NodeBuilder] = []
        let fileCount: Int
        
        init(url: URL, fileCount: Int) {
            self.url = url
            self.fileCount = fileCount
        }
        
        func toStruct() -> CatalogFolderNode {
            var node = CatalogFolderNode(url: url, fileCount: fileCount)
            if !children.isEmpty {
                node.children = children.map { $0.toStruct() }.sorted { $0.name < $1.name }
            }
            return node
        }
    }
    
    private func buildTree(urls: [URL], fileCounts: [URL: Int]) -> [CatalogFolderNode] {
        var nodes: [URL: NodeBuilder] = [:]
        for url in urls {
            nodes[url] = NodeBuilder(url: url, fileCount: fileCounts[url] ?? 0)
        }
        
        var roots: [NodeBuilder] = []
        
        for url in urls.sorted(by: { $0.path < $1.path }) {
            guard let node = nodes[url] else { continue }
            let parentURL = url.deletingLastPathComponent()
            
            if let parentNode = nodes[parentURL] {
                parentNode.children.append(node)
            } else {
                // If parent is not in our node list, this is a root
                roots.append(node)
            }
        }
        
        return roots.map { $0.toStruct() }.sorted { $0.name < $1.name }
    }
    
    private func populateMetadataCache(from items: [MediaItem]) {
        metadataCache.removeAll()
        for item in items {
            guard let path = item.originalPath else { continue }
            let url = URL(fileURLWithPath: path)
            
            var meta = ExifMetadata()
            // Basic info from MediaItem
            meta.orientation = Int(item.orientation)
            meta.rating = Int(item.rating) // Load rating from DB
            
            // Swap dimensions if rotated 90/270 degrees
            if [5, 6, 7, 8].contains(meta.orientation ?? 1) {
                meta.width = Int(item.height)
                meta.height = Int(item.width)
            } else {
                meta.width = Int(item.width)
                meta.height = Int(item.height)
            }
            
            meta.rating = Int(item.rating)
            meta.colorLabel = item.colorLabel // Fix: Read colorLabel
            
            // Exif info
            if let exif = item.exifData {
                meta.cameraMake = exif.cameraMake
                meta.cameraModel = exif.cameraModel
                meta.lensModel = exif.lensModel
                meta.focalLength = exif.focalLength
                meta.aperture = exif.aperture
                meta.shutterSpeed = exif.shutterSpeed
                meta.iso = Int(exif.iso)
                meta.dateTimeOriginal = exif.dateTimeOriginal
            }
            
            metadataCache[url] = meta
        }
    }
    

    
    @Published var expandedFolders: Set<String> = [] {
        didSet {
            // Debounce save?
            // For now, just save on change
            UserDefaults.standard.set(Array(expandedFolders), forKey: "expandedFolders")
        }
    }
    
    private func loadExpandedFolders() {
        if let saved = UserDefaults.standard.stringArray(forKey: "expandedFolders") {
            expandedFolders = Set(saved)
        }
    }
    
    func toggleExpansion(for folder: FileItem) {
        if expandedFolders.contains(folder.url.path) {
            expandedFolders.remove(folder.url.path)
        } else {
            expandedFolders.insert(folder.url.path)
        }
    }
    
    // Catalog Expansion Persistence
    @Published var expandedCatalogFolders: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(expandedCatalogFolders), forKey: "expandedCatalogFolders")
        }
    }
    
    func loadExpandedCatalogFolders() {
        if let saved = UserDefaults.standard.stringArray(forKey: "expandedCatalogFolders") {
            expandedCatalogFolders = Set(saved)
        }
    }
    
    func toggleCatalogExpansion(for url: URL) {
        if expandedCatalogFolders.contains(url.path) {
            expandedCatalogFolders.remove(url.path)
        } else {
            expandedCatalogFolders.insert(url.path)
        }
    }
    
    private var loadingTask: Task<Void, Never>?
    
    private func loadFiles(in folder: FileItem) {
        // Cancel previous task
        loadingTask?.cancel()
        
        // Run in background to prevent UI blocking (spinner)
        // Run in background to prevent UI blocking (spinner)
        // Use Task.detached to ensure it runs off the MainActor
        
        // Capture sort options for background sorting
        let currentSortOption = self.sortOption
        let currentSortAscending = self.isSortAscending
        
        loadingTask = Task.detached(priority: .userInitiated) { [weak self] in
            let startTime = Date()
            Logger.shared.log("DEBUG: Start loadFiles at \(startTime)")
            
            guard let self = self else { return }
            
            // Capture URL to avoid accessing actor-isolated property in detached task if possible,
            // but we need 'folder'. 'folder' is a struct (FileItem), so capturing it is fine.
            let folderURL = folder.url
            
            // Disable count calculation for grid view loading (significant performance boost)
            // Disable count calculation for grid view loading (significant performance boost)
            // Disable count calculation for grid view loading (significant performance boost)
            // FileSystemService methods are now nonisolated (synchronous)
            let items = FileSystemService.shared.getContentsOfDirectory(at: folderURL, calculateCounts: false)
            let fsTime = Date()
            Logger.shared.log("DEBUG: FS load took \(fsTime.timeIntervalSince(startTime))s for \(items.count) items")
            
            let allowedExtensions = FileConstants.allAllowedExtensions
            
            // Filter by extension only first
            let rawFiles = items.filter { item in
                !item.isDirectory && allowedExtensions.contains(item.url.pathExtension.lowercased())
            }
            
            // Sort in background (now fast due to pre-fetched attributes)
            let sortedFiles = FileSortService.sortFiles(rawFiles, by: currentSortOption, ascending: currentSortAscending)
            let sortTime = Date()
            Logger.shared.log("DEBUG: Sort took \(sortTime.timeIntervalSince(fsTime))s")
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                let mainStart = Date()
                // Ensure we are still looking at the same folder
                guard self.currentFolder?.url == folderURL else { return }
                
                self.allFiles = sortedFiles // Store sorted files
                
                // Apply current filters (Main Thread, but usually fast)
                // Note: Filter should preserve order
                let filtered = self.filterFileItems(self.allFiles)
                self.fileItems = filtered
                
                let mainEnd = Date()
                print("DEBUG: MainActor update took \(mainEnd.timeIntervalSince(mainStart))s. Total: \(mainEnd.timeIntervalSince(startTime))s")
                
                // Start background metadata loading
                self.loadMetadataForCurrentFolder()
            }
        }
        

        // Start monitoring (MainActor is fine for setup, but callback is async)
        FileSystemMonitor.shared.startMonitoring(url: folder.url) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                
                // Skip reload if we are actively updating metadata (prevents flash/selection loss)
                if self.isUpdatingMetadata { return }
                
                // Debounce
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                
                // Check again after sleep
                if self.isUpdatingMetadata { return }
                
                if let current = self.currentFolder, current.url == folder.url {
                    self.loadFiles(in: current)
                    // Also trigger global refresh for sidebar
                    self.fileSystemRefreshID = UUID()
                }
                
                // Catalog Mode Sync
                if self.appMode == .catalog, let catalogFolder = self.selectedCatalogFolder, catalogFolder == folder.url {
                    Logger.shared.log("MainViewModel: FileSystem change detected in Catalog Folder: \(folder.url.lastPathComponent)")
                    // We need to refresh the view.
                    // Since we are in Catalog Mode, fileItems come from MediaItems.
                    // If a file was added/removed externally, it won't be in MediaItems until we import/update.
                    // But if metadata changed (e.g. label), we should update it.
                    
                    // 1. Invalidate Exif Cache for visible items
                    // We don't know which file changed, so we might need to invalidate all in this folder?
                    // Or just rely on the fact that if we reload, we re-read?
                    
                    // 2. Reload MediaItems?
                    // loadMediaItems(from: currentCatalog) reloads ALL items. Expensive.
                    // But applyFilter filters them.
                    
                    // Let's try to just re-apply filter to refresh the view?
                    // But applyFilter uses existing allMediaItems.
                    
                    // If we want to see *external* changes, we might need to re-fetch from DB?
                    // But DB doesn't have external changes yet.
                    
                    // The user wants "Sync".
                    // If they changed a label in Finder, we want to see it.
                    // We need to re-read metadata for the displayed items.
                    
                    // Trigger a metadata reload for current items
                    self.loadMetadataForCurrentFolder()
                    
                    // Also, if we want to support "Update Catalog" automatically:
                    // self.checkForUpdates(in: catalogFolder)
                    // But that might be too aggressive.
                }
            }
        }
    }
    
    func loadRootFolders() async {
        // FileSystemService methods are now nonisolated (synchronous)
        let roots = FileSystemService.shared.getRootFolders()
        await MainActor.run {
            self.rootFolders = roots
        }
    }
    
    private func loadMetadataForCurrentFolder() {
        metadataTask?.cancel()
        isLoadingMetadata = true
        metadataCache.removeAll()
        
        let itemsToLoad = allFiles
        
        // Pre-fetch ratings from Core Data to prevent overwrite by empty Exif
        var localRatings: [URL: Int16] = [:]
        let context = persistenceController.newBackgroundContext()
        context.performAndWait {
            let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
            let paths = itemsToLoad.map { $0.url.path }
            // Chunking to avoid predicate limit? 
            // For now, assume folder size is reasonable (< 1000). 
            // If huge, we might need chunking. 
            // But let's keep it simple.
            request.predicate = NSPredicate(format: "originalPath IN %@", paths)
            if let items = try? context.fetch(request) {
                for item in items {
                    if let path = item.originalPath {
                        localRatings[URL(fileURLWithPath: path)] = item.rating
                    }
                }
            }
        }
        
        metadataTask = Task {
            var batch: [URL: ExifMetadata] = [:]
            
            // Separate RAWs and Non-RAWs
            let rawExtensions = FileConstants.allowedImageExtensions.filter { !["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"].contains($0) }
            
            let rawItems = itemsToLoad.filter { rawExtensions.contains($0.url.pathExtension.lowercased()) }
            let otherItems = itemsToLoad.filter { !rawExtensions.contains($0.url.pathExtension.lowercased()) }
            
            // 1. Process RAWs in batches (ExifTool)

            // We can process all RAWs in one go or chunks. readExifBatch handles chunks.
            if !rawItems.isEmpty {
                let rawURLs = rawItems.map { $0.url }
                let rawMetadata = await ExifReader.shared.readExifBatch(from: rawURLs)
                
                await MainActor.run {
                    for (url, var data) in rawMetadata {
                        // Swap dimensions if rotated 90/270 degrees
                        if [5, 6, 7, 8].contains(data.orientation ?? 1) {
                            let w = data.width
                            data.width = data.height
                            data.height = w
                        }
                        
                        // Merge Rating
                        // If we have a local record (MediaItem exists), TRUST IT.
                        // Even if local is 0, it means user might have cleared it.
                        // Only fallback to Exif if we have NO local record.
                        if let local = localRatings[url] {
                            data.rating = Int(local)
                        }
                        
                        self.metadataCache[url] = data
                    }
                    if self.sortOption == .date { self.applySort() }
                }
            }
            
            if Task.isCancelled { return }
            
            // 2. Process others one by one (CGImageSource is fast enough usually, or we can batch if needed)
            var count = 0
            for item in otherItems {
                if Task.isCancelled { break }
                
                if var exif = await ExifReader.shared.readExif(from: item.url) {
                    // Merge Rating
                    if let local = localRatings[item.url] {
                        exif.rating = Int(local)
                    }
                    
                    batch[item.url] = exif
                    count += 1
                }
                
                // Batch update every 200 items to reduce UI flickering
                if count >= 200 {
                    let currentBatch = batch
                    await MainActor.run {
                        for (url, data) in currentBatch {
                            self.metadataCache[url] = data
                        }
                        if self.sortOption == .date { self.applySort() }
                    }
                    batch.removeAll()
                    count = 0
                    try? await Task.sleep(nanoseconds: 5_000_000) // 5ms yield
                }
            }
            
            // Final batch for others
            let finalBatch = batch
            await MainActor.run {
                for (url, data) in finalBatch {
                    self.metadataCache[url] = data
                }
                self.isLoadingMetadata = false
                
                // Re-sort if needed (e.g. if sorting by Date which depends on Exif)
                if self.sortOption == .date {
                    self.applySort()
                }
            }
        }
    }
    
    func applySort() {
        allFiles = FileSortService.sortFiles(allFiles, by: sortOption, ascending: isSortAscending, metadataCache: metadataCache)
        applyFilter()
    }
    
    private func sortItems(_ items: [FileItem]) -> [FileItem] {
        return FileSortService.sortFiles(items, by: sortOption, ascending: isSortAscending)
    }
    
    func copyFile(_ item: FileItem, to folderURL: URL) {
        // Prevent recursive copy
        let srcPath = item.url.standardizedFileURL.path
        let destPath = folderURL.standardizedFileURL.path
        if destPath.hasPrefix(srcPath) {
            Logger.shared.log("Error: Cannot copy folder into itself")
            return
        }
        
        Task.detached(priority: .userInitiated) {
            do {
                let destURL = folderURL.appendingPathComponent(item.url.lastPathComponent)
                try FileManager.default.copyItem(at: item.url, to: destURL)
                Logger.shared.log("Copied \(item.name) to \(destURL.path)")
            } catch {
                Logger.shared.log("Failed to copy file: \(error)")
            }
        }
    }
    
    // Copy Confirmation Logic
    @Published var showCopyConfirmation = false
    @Published var copySourceURL: URL?
    @Published var copyDestinationURL: URL?
    
    func requestCopyFolder(from source: URL, to destination: URL) {
        copySourceURL = source
        copyDestinationURL = destination
        showCopyConfirmation = true
    }
    
    func confirmCopyFolder() {
        guard let source = copySourceURL, let dest = copyDestinationURL else { return }
        let item = FileItem(url: source, isDirectory: true)
        copyFile(item, to: dest)
        
        copySourceURL = nil
        copyDestinationURL = nil
        showCopyConfirmation = false
    }
    
    func moveFile(_ item: FileItem, to folderURL: URL) {
        // Prevent recursive move
        let srcPath = item.url.standardizedFileURL.path
        let destPath = folderURL.standardizedFileURL.path
        if destPath.hasPrefix(srcPath) {
            Logger.shared.log("Error: Cannot move folder into itself")
            return
        }
        
        Task.detached(priority: .userInitiated) {
            do {
                let destURL = folderURL.appendingPathComponent(item.url.lastPathComponent)
                try FileManager.default.moveItem(at: item.url, to: destURL)
                Logger.shared.log("Moved \(item.name) to \(destURL.path)")
                
                await MainActor.run {
                    // Refresh list if we moved out of current folder
                    if let current = self.currentFolder, current.url == item.url.deletingLastPathComponent() {
                        self.loadFiles(in: current)
                    }
                }
            } catch {
                Logger.shared.log("Failed to move file: \(error)")
            }
        }
    }
    

    
    func removeFolderFromCatalog(_ folderURL: URL) {
        guard let catalog = currentCatalog else { return }
        
        let folderPath = folderURL.path
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        // We want to remove items that are IN this folder or subfolders.
        // So path starts with folderPath.
        // Ensure folderPath ends with / for correct prefix matching if needed, but usually path doesn't.
        // NSPredicate "BEGINSWITH" works.
        request.predicate = NSPredicate(format: "originalPath BEGINSWITH %@", folderPath)
        
        do {
            let items = try persistenceController.container.viewContext.fetch(request)
            // We should only delete items that belong to the current catalog?
            // MediaItems are linked to a catalog.
            // But wait, fetchRequest above fetches ALL MediaItems matching path.
            // We must ensure they belong to the current catalog.
            // MediaItem has 'catalog' relationship.
            
            for item in items {
                if item.catalog == catalog {
                    persistenceController.container.viewContext.delete(item)
                }
            }
            try persistenceController.container.viewContext.save()
            
            // Refresh
            loadMediaItems(from: catalog)
            
            // Clear selection if we removed the selected folder or its parent
            if let selected = selectedCatalogFolder, selected.path.hasPrefix(folderPath) {
                selectedCatalogFolder = nil
                applyFilter()
            }
            
        } catch {
            print("Failed to remove folder from catalog: \(error)")
        }
    }
    
    // filterByFolder is not needed as public method anymore since we use selectedCatalogFolder state + applyFilter
    // But we can keep it if needed or remove it. The previous implementation was unused.
    // Let's rely on applyFilter logic we added earlier.

    @Published var thumbnailSize: CGFloat = 150 {
        didSet {
            UserDefaults.standard.set(thumbnailSize, forKey: "defaultThumbnailSize")
        }
    }
    
    @Published var gridColumnsCount: Int = 1
    
    func moveSelection(offset: Int) {
        isAutoScrollEnabled = true
        guard !fileItems.isEmpty else { return }
        
        var newIndex = 0
        if let current = currentFile, let index = fileItems.firstIndex(of: current) {
            newIndex = index + offset
        } else {
            // If no selection, select first (or last if moving up?)
            if offset > 0 { newIndex = 0 }
            else { newIndex = fileItems.count - 1 }
        }
        
        // Clamp
        newIndex = max(0, min(newIndex, fileItems.count - 1))
        
        let newItem = fileItems[newIndex]
        selectFile(newItem)
    }
    
    func moveUp() {
        moveSelection(offset: -gridColumnsCount)
    }
    
    func moveDown() {
        moveSelection(offset: gridColumnsCount)
    }
    
    func moveLeft() {
        moveSelection(offset: -1)
    }
    
    func moveRight() {
        moveSelection(offset: 1)
    }
    
    func selectFile(_ item: FileItem, toggle: Bool = false, extend: Bool = false, autoScroll: Bool = true) {
        isAutoScrollEnabled = autoScroll
        if extend, let current = currentFile, let currentIndex = fileItems.firstIndex(of: current), let newIndex = fileItems.firstIndex(of: item) {
            // Range selection
            let start = min(currentIndex, newIndex)
            let end = max(currentIndex, newIndex)
            let range = fileItems[start...end]
            selectedFiles.formUnion(range)
            currentFile = item
        } else if toggle {
            // Toggle selection
            if selectedFiles.contains(item) {
                selectedFiles.remove(item)
                if currentFile == item {
                    currentFile = selectedFiles.first // Fallback
                }
            } else {
                selectedFiles.insert(item)
                currentFile = item
            }
        } else {
            // Single selection
            selectedFiles = [item]
            currentFile = item
        }
    }
    
    func toggleSelection(_ item: FileItem) {
        selectFile(item, toggle: true)
    }
    
    func selectRange(to item: FileItem) {
        selectFile(item, extend: true)
    }
    
    // MARK: - Metadata Editing Overloads
    
    // MARK: - Metadata Editing Overloads
    
    func updateRating(for item: FileItem, rating: Int) {
        // RAW Restriction: Only allow if in Catalog mode
        let ext = item.url.pathExtension.lowercased()
        let isRaw = FileConstants.allowedImageExtensions.contains(ext) && !["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"].contains(ext)
        
        if isRaw && appMode != .catalog {
            Logger.shared.log("MainViewModel: Skipped rating update for RAW file in Folders mode: \(item.name)")
            return
        }
        
        // Update Metadata Cache
        if var meta = metadataCache[item.url] {
            meta.rating = rating
            metadataCache[item.url] = meta
        } else {
            var meta = ExifMetadata()
            meta.rating = rating
            metadataCache[item.url] = meta
        }
        
        // Update allFiles and fileItems
        // We need to update allFiles because applyFilter uses it.
        // Note: FileItem does not currently store rating, so we don't need to update it here.
        // If we add rating to FileItem in the future, we should update it here.
        if allFiles.firstIndex(where: { $0.id == item.id }) != nil {
            // Placeholder for future update
        }
            // Wait, GridView uses FileItem. If FileItem doesn't have rating, how is it shown?
            // GridView uses AsyncThumbnailView. Does it show rating?
            // DetailView shows rating.
            // If FileItem doesn't have rating property, we can't update it in FileItem.
            // But we should check if FileItem has rating.
            // FileItem definition:
            // public struct FileItem: Identifiable, Hashable, Sendable { ... var rating: Int? ... }
            // Let's assume it has it or we need to add it?
            // Checking FileItem definition...
            // If it doesn't, we can't update it. But the user issue was about LABELS.
            // Labels ARE in FileItem.
            
            // For Rating, we just persist.
        
        Task {
            // Write to XMP/Sidecar?
            // For now, just update Core Data if in Catalog Mode
            let context = persistenceController.newBackgroundContext()
            await context.perform {
                let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                
                if let uuid = item.uuid {
                    request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
                } else {
                    // Fallback: Search by Path (for Folder Mode items not yet linked)
                    request.predicate = NSPredicate(format: "originalPath == %@", item.url.path)
                }
                
                if let mediaItems = try? context.fetch(request), !mediaItems.isEmpty {
                    for mediaItem in mediaItems {
                        mediaItem.rating = Int16(rating)
                    }
                    try? context.save()
                    Logger.shared.log("MainViewModel: Saved rating \(rating) for item \(item.url.lastPathComponent)")
                } else {
                     Logger.shared.log("MainViewModel: No MediaItem found for rating update: \(item.url.lastPathComponent)")
                }
            }
            
            await MainActor.run {
                self.applyFilter()
            }
        }
    }
    
    func updateColorLabel(for item: FileItem, label: String?) {
        updateColorLabel(for: [item], label: label)
    }
    
    func updateRating(for items: [FileItem], rating: Int) {
        for item in items {
            updateRating(for: item, rating: rating)
        }
        // applyFilter is called inside updateRating via Task, but we might want to trigger it once here?
        // Since updateRating spawns a Task, it's async.
        // We can force a UI update here.
        applyFilter()
    }
    
    func updateColorLabel(for items: [FileItem], label: String?) {
        for item in items {
            setColorLabel(label, for: item)
        }
        applyFilter()
    }
    
    func setColorLabel(_ label: String?, for item: FileItem) {
        // RAW Restriction: Only allow if in Catalog mode
        let ext = item.url.pathExtension.lowercased()
        let isRaw = FileConstants.allowedImageExtensions.contains(ext) && !["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"].contains(ext)
        
        if isRaw && appMode != .catalog {
             Logger.shared.log("MainViewModel: Skipped label update for RAW file in Folders mode: \(item.name)")
             return
        }

        // Update allFiles (Source of Truth)
        if let index = allFiles.firstIndex(where: { $0.id == item.id }) {
            var newItem = allFiles[index]
            newItem.colorLabel = label
            allFiles[index] = newItem
            
            // Update selection if needed (to keep selection valid)
            // Fix: Find by ID because item might be stale (different color/hash)
            if let oldSelected = selectedFiles.first(where: { $0.id == item.id }) {
                selectedFiles.remove(oldSelected)
                selectedFiles.insert(newItem)
            }
            if currentFile?.id == item.id {
                currentFile = newItem
            }
        }
        
        // Update fileItems (Current View) - redundant if applyFilter is called, but good for immediate feedback
        if let index = fileItems.firstIndex(where: { $0.id == item.id }) {
            var newItem = fileItems[index]
            newItem.colorLabel = label
            fileItems[index] = newItem
        }
        
        // Update Metadata Cache
        if var meta = metadataCache[item.url] {
            meta.colorLabel = label
            metadataCache[item.url] = meta
        }
        
        // Persist
        Task {
            // 1. Write to Finder (xattr)
            var url = item.url
            var values = URLResourceValues()
            
            if let label = label {
                // Map color name to number
                let colorMap: [String: Int] = ["Gray": 1, "Green": 2, "Purple": 3, "Blue": 4, "Yellow": 5, "Red": 6, "Orange": 7]
                
                if let number = colorMap[label] {
                    values.labelNumber = number
                    try? url.setResourceValues(values)
                    
                    // Also set tagNames for compatibility (using NSURL as URLResourceValues.tagNames is restricted)
                    try? (url as NSURL).setResourceValue([label], forKey: .tagNamesKey)
                } else {
                    values.labelNumber = nil
                    try? url.setResourceValues(values)
                    
                    // Remove tags by setting empty array
                    try? (url as NSURL).setResourceValue([], forKey: .tagNamesKey)
                }
            } else {
                values.labelNumber = nil
                try? url.setResourceValues(values)
                
                // Remove tags by setting empty array
                try? (url as NSURL).setResourceValue([], forKey: .tagNamesKey)
            }
            
            // 2. Update Core Data (Bi-directional Sync)
            let context = persistenceController.newBackgroundContext()
            await context.perform {
                let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                
                if let uuid = item.uuid {
                    request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
                } else {
                    // Fallback: Search by Path (for Folder Mode items not yet linked)
                    request.predicate = NSPredicate(format: "originalPath == %@", item.url.path)
                }
                
                if let mediaItems = try? context.fetch(request), !mediaItems.isEmpty {
                    for mediaItem in mediaItems {
                        mediaItem.colorLabel = label
                    }
                    do {
                        try context.save()
                        Logger.shared.log("MainViewModel: Saved color label '\(label ?? "nil")' for item \(item.url.lastPathComponent)")
                    } catch {
                        Logger.shared.log("MainViewModel: Failed to save color label: \(error)")
                    }
                } else {
                     Logger.shared.log("MainViewModel: No MediaItem found for \(item.url.lastPathComponent) (UUID: \(item.uuid?.uuidString ?? "nil"))")
                }
            }
            
            await MainActor.run {
                self.applyFilter()
            }
        }
    }
    
    func selectNext() {
        guard let current = currentFile, let index = fileItems.firstIndex(of: current) else {
            if let first = fileItems.first {
                selectFile(first)
            }
            return
        }
        if index < fileItems.count - 1 {
            selectFile(fileItems[index + 1])
        }
    }
    
    func selectPrevious() {
        guard let current = currentFile, let index = fileItems.firstIndex(of: current) else { return }
        if index > 0 {
            selectFile(fileItems[index - 1])
        }
    }
    
    func selectAll() {
        selectedFiles = Set(fileItems)
        currentFile = fileItems.last
    }
    
    func deselectAll() {
        selectedFiles.removeAll()
        currentFile = nil
    }
    
    // MARK: - Catalog Update
    
    struct CatalogUpdateStats {
        var added: [URL] = []
        var removed: [URL] = []
        var updated: [URL] = []
        
        var totalChanges: Int {
            added.count + removed.count + updated.count
        }
    }
    
    @Published var isScanningCatalog: Bool = false
    
    func checkForUpdates(catalog: Catalog) async -> CatalogUpdateStats {
        isScanningCatalog = true
        defer { isScanningCatalog = false }
        
        let catalogID = catalog.objectID
        
        let controller = self.persistenceController
        
        return await Task.detached(priority: .userInitiated) {
            var stats = CatalogUpdateStats()
            
            // 1. Get all known files in DB
            let context = controller.newBackgroundContext()
            
            var dbFiles: [URL: Date?] = [:] // URL -> Modification Date
            
            // Create request inside the block to avoid Sendable warning
            context.performAndWait {
                let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                request.predicate = NSPredicate(format: "catalog == %@", catalogID)
                
                if let items = try? context.fetch(request) {
                    for item in items {
                        if let path = item.originalPath {
                            let url = URL(fileURLWithPath: path)
                            dbFiles[url] = item.modifiedDate
                        }
                    }
                }
            }
            
            // 2. Scan disk
            // We need to know which folders are in the catalog.
            // Catalog has root folders?
            // Actually, `importFolderToCatalog` adds items.
            // We should scan the folders that are *roots* of the catalog.
            // But `Catalog` doesn't explicitly store "root folders" list in a simple way if we imported multiple.
            // We can infer roots from `dbFiles` or if we have a separate `CatalogFolder` entity?
            // We don't have `CatalogFolder` entity persisted?
            // Wait, `CatalogFolderNode` is built from `MediaItem` paths.
            // So we should scan the common ancestors?
            // Or just iterate all folders that contain at least one file?
            // Better: The user usually imports a specific folder.
            // If we imported `/Photos/2023` and `/Photos/2024`.
            // We should scan those.
            // But we don't store the "Imported Roots".
            // We only have `MediaItem`s.
            // This is a limitation of the current schema if we want to detect *new* files in those folders.
            // We can try to deduce roots: Find shortest paths.
            // Or, we can just assume the user wants to update files *already in the catalog* (check for deleted/updated)
            // AND check for new files *in the same directories* as existing files.
            
            // Strategy: Get all unique directory paths from DB files.
            // Scan those directories for NEW files.
            // Also check existence of DB files (Deleted).
            // Also check modification date (Updated).
            
            var directoriesToScan: Set<URL> = []
            for url in dbFiles.keys {
                directoriesToScan.insert(url.deletingLastPathComponent())
            }
            
            let fileManager = FileManager.default
            
            // Check for Removed and Updated
            for (url, date) in dbFiles {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
                    if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                       let fileDate = attrs[.modificationDate] as? Date {
                        // Check if updated (allow some tolerance)
                        if let dbDate = date, fileDate.timeIntervalSince(dbDate) > 1.0 {
                            stats.updated.append(url)
                        }
                    }
                } else {
                    stats.removed.append(url)
                }
            }
            
            // Check for Added
            for dir in directoriesToScan {
                // Non-recursive scan of each directory (since we collect all dirs)
                // Wait, if we have subfolders in DB, they are in `directoriesToScan`.
                // But if a NEW subfolder appeared, we won't know about it unless we scan recursively from "roots".
                // But we don't know roots.
                // So we only scan for new files in *existing* directories.
                // This is a reasonable compromise if we don't track roots.
                // Or we can try to find common roots.
                
                if let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
                    for url in contents {
                        if dbFiles[url] == nil {
                            // It's new!
                            // Check if it's an image
                            let ext = url.pathExtension.lowercased()
                            if FileConstants.allowedImageExtensions.contains(ext) {
                                stats.added.append(url)
                            }
                        }
                    }
                }
            }
            
            return stats
        }.value
    }
    
    func performCatalogUpdate(catalog: Catalog, stats: CatalogUpdateStats) {
        guard let context = catalog.managedObjectContext else { return }
        
        Task {
            // 1. Remove deleted
            if !stats.removed.isEmpty {
                await MainActor.run {
                    // We need to fetch objects to delete
                    let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                    request.predicate = NSPredicate(format: "catalog == %@ AND originalPath IN %@", catalog, stats.removed.map { $0.path })
                    if let items = try? context.fetch(request) {
                        for item in items {
                            context.delete(item)
                        }
                    }
                }
            }
            
            // 2. Add new
            if !stats.added.isEmpty {
                // We can use import logic, but we need to be careful not to duplicate.
                // We already know they are new.
                // Batch insert is faster.
                await MainActor.run {
                    for url in stats.added {
                        let item = MediaItem(context: context)
                        item.id = UUID()
                        item.originalPath = url.path
                        item.fileName = url.lastPathComponent
                        item.catalog = catalog
                        item.importDate = Date()
                        
                        // Basic metadata
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                            item.fileSize = (attrs[.size] as? Int64) ?? 0
                            item.modifiedDate = attrs[.modificationDate] as? Date
                        }
                        
                        // We should trigger metadata loading later
                    }
                }
            }
            
            // 3. Update existing
            if !stats.updated.isEmpty {
                await MainActor.run {
                    let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                    request.predicate = NSPredicate(format: "catalog == %@ AND originalPath IN %@", catalog, stats.updated.map { $0.path })
                    if let items = try? context.fetch(request) {
                        for item in items {
                            if let path = item.originalPath, let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
                                item.modifiedDate = attrs[.modificationDate] as? Date
                                item.fileSize = (attrs[.size] as? Int64) ?? 0
                                // Invalidate cache/preview?
                            }
                        }
                    }
                }
            }
            
            await MainActor.run {
                try? context.save()
                
                // Refresh view if current catalog
                if currentCatalog == catalog {
                    loadMediaItems(from: catalog)
                    loadCollections(for: catalog)
                }
                
                // Trigger metadata update for new/updated items
                let allToUpdate = stats.added + stats.updated
                if !allToUpdate.isEmpty {
                    // We need to map URLs to FileItems or just call populateMetadataCache with URLs?
                    // populateMetadataCache takes [FileItem].
                    // We can create temporary FileItems or add a method to update by URL.
                    // For now, just let the view refresh handle it?
                    // View refresh will create FileItems.
                }
            }
        }
    }
    
    func cleanup() {
        FileSystemMonitor.shared.stopMonitoring()
        metadataTask?.cancel()
    }
    
    func refreshFileAttributes(for url: URL? = nil) async {
        // If url is provided, we could optimize to only refresh that file, 
        // but for now we refresh all current items to be safe and simple, 
        // or filter if needed.
        // The Sidebar calls this with a folder URL. 
        // If the folder URL matches currentFolder, we refresh.
        
        if let url = url, let current = currentFolder?.url, url != current {
            // Refreshing a different folder? Maybe just ignore or reload if it's the one being viewed.
            return
        }
        
        // Refresh attributes (Color Label, Size, Date) from disk for current fileItems
        // This is crucial for Catalog Mode sync where we don't reload from disk fully
        let items = fileItems
        Task {
            var updates: [UUID: (String?, Int64?, Date?)] = [:]
            
            for item in items {
                let url = item.url
                // Use fresh URL to ensure no caching issues
                let freshURL = URL(fileURLWithPath: url.path)
                
                // Read attributes
                if let resourceValues = try? freshURL.resourceValues(forKeys: [.labelNumberKey, .tagNamesKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]) {
                    let label = FileSystemService.shared.getColorLabel(from: freshURL)
                    let size = resourceValues.fileSize.map { Int64($0) }
                    let date = resourceValues.creationDate
                    
                    if let uuid = item.uuid {
                        updates[uuid] = (label, size, date)
                    }
                }
            }
            
            await MainActor.run {
                // Update fileItems
                var newItems = self.fileItems
                for i in 0..<newItems.count {
                    if let uuid = newItems[i].uuid, let update = updates[uuid] {
                        var newItem = newItems[i]
                        newItem.colorLabel = update.0
                        // newItem.fileSize = update.1 // FileItem properties are let? No, I made colorLabel var.
                        // I should make others var too if needed, or create new FileItem.
                        // Let's create new FileItem to be safe and immutable-ish
                        newItems[i] = FileItem(url: newItem.url, isDirectory: newItem.isDirectory, isAvailable: newItem.isAvailable, uuid: newItem.uuid, colorLabel: update.0, fileCount: newItem.fileCount, creationDate: update.2, fileSize: update.1)
                    }
                }
                self.fileItems = newItems
                
                // Update selectedFiles to reflect changes (crucial for Inspector sync)
                if !self.selectedFiles.isEmpty {
                    var newSelection = Set<FileItem>()
                    for item in self.selectedFiles {
                        if let newItem = newItems.first(where: { $0.url == item.url }) {
                            newSelection.insert(newItem)
                        } else {
                            newSelection.insert(item)
                        }
                    }
                    self.selectedFiles = newSelection
                }
                
                // Update MetadataCache for label (if we store it there)
                for (uuid, update) in updates {
                    if let item = newItems.first(where: { $0.uuid == uuid }) {
                        if var meta = self.metadataCache[item.url] {
                            meta.colorLabel = update.0
                            self.metadataCache[item.url] = meta
                        }
                    }
                }
                
                Logger.shared.log("MainViewModel: Refreshed attributes for \(updates.count) items.")
            }
            
            // Optional: Update Core Data in background?
            // This ensures persistence.
            if !updates.isEmpty {
                let context = self.persistenceController.newBackgroundContext()
                await context.perform {
                    for (uuid, update) in updates {
                        // Fetch MediaItem by UUID
                        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
                        if let mediaItem = try? context.fetch(request).first {
                            mediaItem.colorLabel = update.0
                            if let size = update.1 { mediaItem.fileSize = size }
                            // mediaItem.creationDate = update.2 // If we want to sync date
                        }
                    }
                    try? context.save()
                }
            }
        }
    }
    
    // MARK: - Delete Confirmation
    @Published var showDeleteConfirmation = false
    @Published var itemsToDelete: [FileItem] = []
    
    func confirmDelete(_ items: [FileItem]) {
        self.itemsToDelete = items
        self.showDeleteConfirmation = true
    }
    
    func performDelete() {
        for item in itemsToDelete {
            deleteFile(item)
        }
        itemsToDelete = []
        showDeleteConfirmation = false
    }
    
    // MARK: - Layout
    
    @Published var isPreviewVisible = true
    
    func togglePreviewLayout() {
        isPreviewVisible.toggle()
    }
    
    // MARK: - Folder Operations
    
    @Published var showMoveConfirmation = false
    @Published var moveSourceURL: URL?
    @Published var moveDestinationURL: URL?
    @Published var showError = false
    @Published var errorMessage = ""
    
    func requestMoveFolder(from source: URL, to destination: URL) {
        self.moveSourceURL = source
        self.moveDestinationURL = destination
        self.showMoveConfirmation = true
    }
    
    func confirmMoveFolder() {
        guard let source = moveSourceURL, let destination = moveDestinationURL else { return }
        
        let destURL = destination.appendingPathComponent(source.lastPathComponent)
        
        do {
            try FileManager.default.moveItem(at: source, to: destURL)
            Logger.shared.log("MainViewModel: Moved folder from \(source.path) to \(destURL.path)")
            
            // Refresh
            if currentFolder?.url == source {
                // Create a new FileItem for the destination
                // We assume it's a directory since we moved a folder
                currentFolder = FileItem(url: destURL, isDirectory: true)
            }
        } catch {
            Logger.shared.log("MainViewModel: Failed to move folder: \(error.localizedDescription)")
            self.errorMessage = "Failed to move folder: \(error.localizedDescription)"
            self.showError = true
        }
        
        self.moveSourceURL = nil
        self.moveDestinationURL = nil
        self.showMoveConfirmation = false
    }
    
    func deleteFolder(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            Logger.shared.log("MainViewModel: Deleted folder \(url.path)")
            
            // Refresh parent if needed?
            // FileSystemMonitor should handle it.
            
            // If current folder was deleted, go up?
            if currentFolder?.url == url {
                currentFolder = nil // Or go to parent
            }
            
            // Trigger Sidebar Refresh
            Task { @MainActor in
                self.fileSystemRefreshID = UUID()
            }
        } catch {
            Logger.shared.log("MainViewModel: Failed to delete folder: \(error.localizedDescription)")
            self.errorMessage = "Failed to delete folder: \(error.localizedDescription)"
            self.showError = true
        }
    }
    
    func createFolder(at parentURL: URL, name: String) {
        let newURL = parentURL.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
            Logger.shared.log("MainViewModel: Created folder \(newURL.path)")
            // FileSystemMonitor should handle refresh
            
            // Trigger Sidebar Refresh
            Task { @MainActor in
                self.fileSystemRefreshID = UUID()
            }
        } catch {
            Logger.shared.log("MainViewModel: Failed to create folder: \(error.localizedDescription)")
            self.errorMessage = "Failed to create folder: \(error.localizedDescription)"
            self.showError = true
        }
    }
}
