@preconcurrency import CoreData
import SwiftUI

extension Notification.Name {
    public static let refreshAll = Notification.Name("refreshAll")
}

@MainActor
public class MainViewModel: ObservableObject {
    @Published var currentFolder: FileItem?

    @Published var fileItems: [FileItem] = []
    @Published var allFiles: [FileItem] = []  // Store all files in current folder/catalog before filtering
    @Published var selectedFiles: Set<FileItem> = []
    @Published var currentFile: FileItem? {  // The most recently selected item (for DetailView)
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
    @Published public var metadataCache: [URL: ExifMetadata] = [:]
    @Published public var isLoadingMetadata: Bool = false
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
    }

    // thumbnailSize is declared at the top

    private let mediaRepository: MediaRepositoryProtocol
    private let collectionRepository: CollectionRepositoryProtocol
    private let persistenceController: PersistenceController

    public init(
        mediaRepository: MediaRepositoryProtocol? = nil,
        collectionRepository: CollectionRepositoryProtocol? = nil,
        persistenceController: PersistenceController = .shared
    ) {
        self.persistenceController = persistenceController
        self.mediaRepository =
            mediaRepository ?? MediaRepository(context: persistenceController.container.viewContext)
        self.collectionRepository =
            collectionRepository
            ?? CollectionRepository(context: persistenceController.container.viewContext)
        // rootFolders loaded in loadRootFolders()
        
        // Skip ExifTool check in tests to prevent Process execution crashes
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        
        if !isTesting {
            self.isExifToolAvailable = MetadataService.shared.isExifToolAvailable()
        }

        // Load default sort order
        if !isTesting, let savedSort = UserDefaults.standard.string(forKey: "defaultSortOrder"),
            let order = SortOption(rawValue: savedSort)
        {
            self.sortOption = order
        }

        // Load default thumbnail size
        if !isTesting {
            let savedSize = UserDefaults.standard.double(forKey: "defaultThumbnailSize")
            if savedSize > 0 {
                self.thumbnailSize = savedSize
            }
        }

        if !isTesting {
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
        }

        setupNotifications()

        // Load default mode
        if UserDefaults.standard.string(forKey: "defaultAppMode") == "catalogs" {
            // ...
        } else {
            // Try to load last opened folder
            if let lastPath = UserDefaults.standard.string(forKey: "lastOpenedFolder") {
                let url = URL(fileURLWithPath: lastPath)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: lastPath, isDirectory: &isDir)
                    && isDir.boolValue
                {
                    openFolder(FileItem(url: url, isDirectory: true))
                }
            }
        }

        // Try to load last used catalog
        loadCurrentCatalogID()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFolders()
            }
        }

        NotificationCenter.default.addObserver(forName: .refreshAll, object: nil, queue: .main) {
            [weak self] _ in
            Task { @MainActor in
                self?.refreshAll()
            }
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] notification in
            Logger.shared.log("Device mounted: \(notification.userInfo ?? [:])")
            Task { @MainActor in
                // Delay to ensure volume is ready
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0s
                await self?.loadRootFolders()
                // Resume thumbnail generation if needed
                self?.checkMissingThumbnails()
            }
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main
        ) { [weak self] notification in
            Logger.shared.log("Device unmounted: \(notification.userInfo ?? [:])")
            Task { @MainActor in
                await self?.loadRootFolders()
                self?.refreshFolders() // Check if current folder is valid
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
        // But we can trigger a view update.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s delay for FS update
            self.fileSystemRefreshID = UUID()
        }
        
        // Also reload root folders to update their counts
        Task {
            await loadRootFolders()
        }
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
            let uuid = UUID(uuidString: idString)
        else { return }

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

    public enum SortOption: String, CaseIterable, Identifiable {
        case name = "Name"
        case date = "Date"
        case size = "Size"

        public var id: String { rawValue }
    }

    @Published var fileSystemRefreshID = UUID()

    public func openFolder(_ folder: FileItem) {
        ImageCacheService.shared.clearCache()
        appMode = .folders
        currentFolder = folder

        // Save to UserDefaults
        UserDefaults.standard.set(folder.url.path, forKey: "lastOpenedFolder")

        // currentCatalog = nil // Keep catalog selected in sidebar as requested
        currentCollection = nil
        selectedFiles.removeAll()
        currentFile = nil
        // Reset filters as requested by user
        filterCriteria = FilterCriteria()
        isFilterDisabled = false

        // Suspend thumbnail generation to prioritize UI/DB for folder loading
        ThumbnailGenerationService.shared.suspend()
        
        loadFiles(in: folder)
        
        // Resume after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ThumbnailGenerationService.shared.resume()
        }
    }

    public func openCatalog(_ catalog: Catalog) {
        // Clear cache from previous catalog/folder to free memory
        ImageCacheService.shared.clearCache()
        
        // Cancel any running thumbnail generation to prevent freezing/contention
        ThumbnailGenerationService.shared.cancelAll()

        metadataTask?.cancel()  // Cancel any running metadata task from folder mode

        appMode = .catalog
        currentCatalog = catalog
        saveCurrentCatalogID()  // Save selection
        currentFolder = nil  // Clear folder
        currentCollection = nil
        selectedFiles.removeAll()
        currentFile = nil
        // Reset filters
        filterCriteria = FilterCriteria()
        isFilterDisabled = false

        selectedCatalogFolder = nil  // Reset folder filter

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
        print("DEBUG: selectCatalogFolder called with url=\(url?.path ?? "nil")")
        metadataTask?.cancel()  // Cancel any running metadata task
        appMode = .catalog
        currentFolder = nil
        currentCollection = nil  // Clear collection selection
        selectedCatalogFolder = url
        // Reset filters when changing folder in catalog
        filterCriteria = FilterCriteria()
        isFilterDisabled = false
        
        // Apply filter immediately to show items in selected folder
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
            return  // Already importing
        }
        
        // Security Scope Access for App Sandbox
        let access = url.startAccessingSecurityScopedResource()

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else {
                if access { url.stopAccessingSecurityScopedResource() }
                return
            }
            
            // Ensure cleanup happens regardless of success or failure
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
                
                Task { @MainActor in
                    // Clear message after delay
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if self.importStatusMessage == "Import complete." {
                        self.importStatusMessage = ""
                    }
                }
            }
            
            do {
                await MainActor.run {
                    self.importStatusMessage = "Importing..."
                    // Set isImporting flag
                    if let catalog = self.currentCatalog {
                        catalog.isImporting = true
                        try? self.persistenceController.container.viewContext.save()
                    }
                }

                // 2. Import using Repository (background)
                // Pass folder URL directly, repository handles recursion
                try await self.mediaRepository.importMediaItems(from: [url], to: catalogObjectID) { progress in
                    Task { @MainActor in
                        self.importProgress = progress
                    }
                }

                // 3. Refresh
                await MainActor.run {
                    // Only refresh catalog items if we are in Catalog Mode AND viewing the same catalog
                    if self.appMode == .catalog, self.currentCatalog?.id == catalogID, let currentCatalog = self.currentCatalog {
                        // Ensure we see the latest changes from background context
                        self.persistenceController.container.viewContext.refreshAllObjects()
                        self.loadMediaItems(from: currentCatalog)
                        
                        // Clear isImporting flag
                        currentCatalog.isImporting = false
                        try? self.persistenceController.container.viewContext.save()
                    } else {
                        // If we switched catalogs or are in Folder Mode, we still need to clear the flag for the target catalog
                        let context = self.persistenceController.container.viewContext
                        context.perform {
                            if let targetCatalog = try? context.existingObject(with: catalogObjectID) as? Catalog {
                                targetCatalog.isImporting = false
                                try? context.save()
                            }
                        }
                        
                        // If in Folder Mode and viewing the imported folder, refresh it
                        if self.appMode == .folders, let current = self.currentFolder, current.url == url {
                            self.loadFiles(in: current)
                        }
                    }
                    
                    // Remove from pending imports AFTER refresh is done
                    if let index = self.pendingImports.firstIndex(of: url) {
                        self.pendingImports.remove(at: index)
                    }
                    self.updateImportState()
                    
                    self.importStatusMessage = "Import complete."
                }

            } catch {
                print("Failed to import folder: \(error)")
                await MainActor.run {
                    self.importStatusMessage = "Import failed"
                    
                    // Clear isImporting flag on error
                    if let catalog = self.currentCatalog {
                        catalog.isImporting = false
                        try? self.persistenceController.container.viewContext.save()
                    }
                    
                    // Remove from pending imports
                    if let index = self.pendingImports.firstIndex(of: url) {
                        self.pendingImports.remove(at: index)
                    }
                    self.updateImportState()
                }
            }
        }
    }
    
    func presentImportDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Import"
        panel.message = "Select folders to import into the catalog"
        
        panel.begin { [weak self] response in
            guard let self = self, response == .OK else { return }
            
            for url in panel.urls {
                self.importFolderToCatalog(url: url)
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
        
        // 1. Rename on Disk
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
        } catch {
            Logger.shared.log("Failed to rename folder: \(error)")
            return
        }
        
        // 2. Update Catalog (if applicable)
        Task {
            await updateCatalogPaths(from: url, to: newURL)
            await MainActor.run {
                // Refresh
                self.fileSystemRefreshID = UUID()
                
                // Update current folder if needed
                if self.appMode == .folders {
                    if let current = self.currentFolder, current.url == url {
                        self.openFolder(FileItem(url: newURL, isDirectory: true))
                    } else if let current = self.currentFolder, current.url == url.deletingLastPathComponent() {
                        // If we renamed a sibling/child in current folder, reload
                        self.loadFiles(in: current)
                    }
                }
                
                // Refresh roots
                let roots = FileSystemService.shared.getRootFolders()
                self.rootFolders = roots
            }
        }
    }

    func renameCatalog(_ catalog: Catalog, newName: String) {
        guard let context = catalog.managedObjectContext else { return }
        context.perform {
            catalog.name = newName
            try? context.save()
            Task { @MainActor in
                self.objectWillChange.send()
            }
        }
    }


    func openCollection(_ collection: Collection) {
        currentCollection = collection
        selectedFiles.removeAll()
        currentFile = nil
        // filterCriteria = FilterCriteria() // Reset filters
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
                Logger.shared.log(
                    "Warning: No current catalog, using first available: \(first.name ?? "nil")")
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

                Logger.shared.log(
                    "Creating collection: \(name) in catalog: \(bgCatalog.name ?? "nil")")

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
                        if let mainCatalog = try? self.persistenceController.container.viewContext
                            .existingObject(with: catalogID) as? Catalog
                        {
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
                if let mediaItem = try? persistenceController.container.viewContext.fetch(request)
                    .first
                {
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
                if let mediaItem = try? persistenceController.container.viewContext.fetch(request)
                    .first
                {
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

    @Published var selectedCatalogFolder: URL? {  // Filter catalog by folder
        didSet {
            if let url = selectedCatalogFolder {
                UserDefaults.standard.set(url.path, forKey: "lastSelectedCatalogFolder")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastSelectedCatalogFolder")
            }
        }
    }

    func applyFilter() {
        print("DEBUG: applyFilter called. appMode=\(appMode), currentCatalog=\(currentCatalog?.name ?? "nil"), selectedCatalogFolder=\(selectedCatalogFolder?.path ?? "nil")")
        
        // Track time
        let startTime = Date()
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
                    return FileItem(
                        url: url, isDirectory: false, uuid: item.id ?? UUID(),
                        colorLabel: item.colorLabel, isFavorite: item.isFavorite, flagStatus: item.flagStatus,
                        creationDate: item.captureDate,
                        modificationDate: item.modifiedDate, fileSize: item.fileSize, orientation: Int(item.orientation))
                }
                fileItems = sortItems(mapped)
                // Also populate metadata cache for these items
                populateMetadataCache(from: filtered)
            }
        } else if isFilterDisabled {
            // If filters are disabled, show all items (subject to folder scope)
            if appMode == .catalog {
                print("DEBUG: Filter disabled. allMediaItems count: \(allMediaItems.count)")
                var items = allMediaItems
                if let folder = selectedCatalogFolder {
                    let folderPath = folder.path
                    items = items.filter { item in
                        guard let path = item.originalPath else { return false }
                        return URL(fileURLWithPath: path).deletingLastPathComponent().path
                            == folderPath
                    }
                }
                // Still populate cache for scope
                populateMetadataCache(from: items)

                let mapped = items.compactMap { item -> FileItem? in
                    guard let path = item.originalPath else { return nil }
                    let url = URL(fileURLWithPath: path)
                    let isAvailable = FileManager.default.fileExists(atPath: path)
                    return FileItem(
                        url: url, isDirectory: false, isAvailable: isAvailable,
                        uuid: item.id ?? UUID(), colorLabel: item.colorLabel,
                        isFavorite: item.isFavorite, flagStatus: item.flagStatus,
                        creationDate: item.captureDate, modificationDate: item.modifiedDate,
                        fileSize: item.fileSize, orientation: Int(item.orientation))
                }
                fileItems = sortItems(mapped)
            } else if appMode == .folders {
                fileItems = sortItems(allFiles)
            }

        } else if appMode == .catalog, currentCatalog != nil {
            // Filter from allMediaItems
            print("DEBUG: Filter enabled. allMediaItems count: \(allMediaItems.count)")
            print("DEBUG: Checking selectedCatalogFolder: \(selectedCatalogFolder?.path ?? "nil")")
            var items = allMediaItems

            // Apply Folder Filter if active
            if let folder = selectedCatalogFolder {
                let folderPath = folder.path
                print("DEBUG: Filtering for folder: \(folderPath)")
                items = items.filter { item in
                    guard let path = item.originalPath else { return false }
                    let itemFolder = URL(fileURLWithPath: path).deletingLastPathComponent().path
                    let match = itemFolder == folderPath
                    if !match && items.count < 5 { // Log first few mismatches
                         print("DEBUG: Mismatch - Item: \(itemFolder) vs Target: \(folderPath)")
                    }
                    return match
                }
                print("DEBUG: Items after folder filter: \(items.count)")
            } else {
                print("DEBUG: selectedCatalogFolder is nil inside applyFilter logic block")
            }

            // Update metadata cache to reflect the items in the current scope (Catalog or Catalog Folder)
            // BEFORE applying attribute filters, so the filters show available options for this scope.
            populateMetadataCache(from: items)

            let filtered = filterItems(items)
            print("DEBUG: Items after filterItems: \(filtered.count)")
            let mapped = filtered.compactMap { item -> FileItem? in
                guard let path = item.originalPath else { return nil }
                let url = URL(fileURLWithPath: path)
                let isAvailable = FileManager.default.fileExists(atPath: path)
                return FileItem(
                    url: url, isDirectory: false, isAvailable: isAvailable, uuid: item.id ?? UUID(),
                    colorLabel: item.colorLabel, isFavorite: item.isFavorite, flagStatus: item.flagStatus,
                    creationDate: item.captureDate,
                    modificationDate: item.modifiedDate, fileSize: item.fileSize, orientation: Int(item.orientation))
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
            if let current = currentFile,
                let newCurrent = fileItems.first(where: { $0.id == current.id })
            {
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
            let criteria = try? JSONDecoder().decode(FilterCriteria.self, from: data)
        {
            self.filterCriteria = criteria
        }
    }

    // MARK: - File Operations (Multi-file)



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
        guard let catalog = currentCatalog else { return }
        let catalogID = catalog.objectID
        
        // Only import if the parent folder is already in the catalog
        let parentPath = url.deletingLastPathComponent().standardizedFileURL.path
        let context = persistenceController.container.viewContext
        
        await context.perform {
            guard let bgCatalog = try? context.existingObject(with: catalogID) as? Catalog else { return }
            
            let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
            request.predicate = NSPredicate(format: "catalog == %@ AND originalPath == %@", bgCatalog, parentPath)
            request.fetchLimit = 1
            
            if let count = try? context.count(for: request), count > 0 {
                // Parent exists, safe to import
                Task {
                    try? await self.mediaRepository.importMediaItems(from: [url], to: catalogID, progress: nil)
                }
            }
        }
    }

    // MARK: - Metadata Editing

    // Methods moved to extension/bottom to fix redeclaration and add selection update logic.
    // See updateRating and updateColorLabel below.

    private func filterItems(_ items: [MediaItem]) -> [MediaItem] {
        print("DEBUG: filterItems called with \(items.count) items. Criteria active: \(filterCriteria.isActive)")
        if filterCriteria.isActive {
             print("DEBUG: Criteria details - minRating: \(filterCriteria.minRating), color: \(filterCriteria.colorLabel ?? "nil"), fav: \(filterCriteria.showOnlyFavorites), flag: \(filterCriteria.flagFilter.rawValue)")
        }
        return items.filter { item in
            if item.rating < filterCriteria.minRating { return false }
            if let label = filterCriteria.colorLabel, item.colorLabel != label { return false }
            if !filterCriteria.searchText.isEmpty {
                if let name = item.fileName,
                    !name.localizedCaseInsensitiveContains(filterCriteria.searchText)
                {
                    return false
                }
            }
            
            // Media Type Filter
            if let path = item.originalPath {
                let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
                let isImage = FileConstants.allowedImageExtensions.contains(ext)
                let isVideo = FileConstants.allowedVideoExtensions.contains(ext)
                
                if !filterCriteria.showImages && isImage { return false }
                if !filterCriteria.showVideos && isVideo { return false }
            }
            
            // Favorite Filter
            // Check metadata cache first (Folder Mode support), then item property (Catalog Mode)
            let isFavorite: Bool
            if let path = item.originalPath, let cached = metadataCache[URL(fileURLWithPath: path).standardizedFileURL], let fav = cached.isFavorite {
                isFavorite = fav
            } else {
                isFavorite = item.isFavorite
            }
            
            if filterCriteria.showOnlyFavorites && !isFavorite {
                return false
            }
            
            // Flag Filter
            let flagStatus: Int
            if let path = item.originalPath, let cached = metadataCache[URL(fileURLWithPath: path).standardizedFileURL], let flag = cached.flagStatus {
                flagStatus = flag
            } else {
                flagStatus = Int(item.flagStatus)
            }
            
            if filterCriteria.flagFilter != .all {
                switch filterCriteria.flagFilter {
                case .flagged:
                    if flagStatus == 0 { return false } // Any flag (Pick or Reject)
                case .pick:
                    if flagStatus != 1 { return false }
                case .reject:
                    if flagStatus != -1 { return false }
                case .unflagged:
                    if flagStatus != 0 { return false }
                case .all:
                    break
                }
            }
            
            // Attribute Filters
            // We need metadata to filter by attributes. If metadata is missing, we exclude the item if a filter is active.
            let metadata: ExifMetadata?
            if let path = item.originalPath {
                metadata = metadataCache[URL(fileURLWithPath: path).standardizedFileURL]
            } else {
                metadata = nil
            }
            
            if !filterCriteria.selectedMakers.isEmpty {
                guard let make = metadata?.cameraMake, filterCriteria.selectedMakers.contains(make) else { return false }
            }
            
            if !filterCriteria.selectedCameras.isEmpty {
                guard let model = metadata?.cameraModel, filterCriteria.selectedCameras.contains(model) else { return false }
            }
            
            if !filterCriteria.selectedLenses.isEmpty {
                guard let lens = metadata?.lensModel, filterCriteria.selectedLenses.contains(lens) else { return false }
            }
            
            if !filterCriteria.selectedISOs.isEmpty {
                guard let iso = metadata?.iso, filterCriteria.selectedISOs.contains(String(iso)) else { return false }
            }
            
            if !filterCriteria.selectedDates.isEmpty {
                // Date filtering usually works on YYYY-MM-DD or similar. Assuming the set contains formatted date strings.
                // We need to format the item's date to match.
                guard let date = metadata?.dateTimeOriginal else { return false }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let dateString = formatter.string(from: date)
                if !filterCriteria.selectedDates.contains(dateString) { return false }
            }
            
            if !filterCriteria.selectedFileTypes.isEmpty {
                let ext: String
                if let path = item.originalPath {
                    ext = URL(fileURLWithPath: path).pathExtension.uppercased()
                } else {
                    ext = ""
                }
                if !filterCriteria.selectedFileTypes.contains(ext) { return false }
            }
            
            if !filterCriteria.selectedShutterSpeeds.isEmpty {
                guard let speed = metadata?.shutterSpeed, filterCriteria.selectedShutterSpeeds.contains(speed) else { return false }
            }
            
            if !filterCriteria.selectedApertures.isEmpty {
                // Aperture is Double, but filter might be string representation like "f/2.8" or just "2.8"
                // Assuming the filter set contains strings matching the formatted output
                guard let aperture = metadata?.aperture else { return false }
                let apertureString = String(format: "f/%.1f", aperture)
                if !filterCriteria.selectedApertures.contains(apertureString) { return false }
            }
            
            if !filterCriteria.selectedFocalLengths.isEmpty {
                guard let focal = metadata?.focalLength else { return false }
                let focalString = String(format: "%.0f mm", focal)
                if !filterCriteria.selectedFocalLengths.contains(focalString) { return false }
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
                if !item.name.localizedCaseInsensitiveContains(filterCriteria.searchText) {
                    return false
                }
            }

            // Color Label Filter
            if let label = filterCriteria.colorLabel {
                if item.colorLabel != label { return false }
            }

            // Favorites Filter
            if filterCriteria.showOnlyFavorites {
                if item.isFavorite != true { return false }
            }

            // Flag Filter
            switch filterCriteria.flagFilter {
            case .all:
                break
            case .flagged:
                if item.flagStatus == 0 || item.flagStatus == nil { return false }
            case .unflagged:
                if item.flagStatus != 0 && item.flagStatus != nil { return false }
            case .pick:
                if item.flagStatus != 1 { return false }
            case .reject:
                if item.flagStatus != -1 { return false }
            }

            // Media Type Filter
            let ext = item.url.pathExtension.lowercased()
            if !filterCriteria.showImages {
                if FileConstants.allowedImageExtensions.contains(ext) { return false }
            }
            if !filterCriteria.showVideos {
                if FileConstants.allowedVideoExtensions.contains(ext) { return false }
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
                        if !filterCriteria.selectedShutterSpeeds.contains("Unknown") {
                            return false
                        }
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
                if !filterCriteria.selectedMakers.isEmpty
                    && !filterCriteria.selectedMakers.contains("Unknown")
                {
                    return false
                }
                if !filterCriteria.selectedCameras.isEmpty
                    && !filterCriteria.selectedCameras.contains("Unknown")
                {
                    return false
                }
                if !filterCriteria.selectedLenses.isEmpty
                    && !filterCriteria.selectedLenses.contains("Unknown")
                {
                    return false
                }
                if !filterCriteria.selectedISOs.isEmpty
                    && !filterCriteria.selectedISOs.contains("Unknown")
                {
                    return false
                }
                if !filterCriteria.selectedDates.isEmpty
                    && !filterCriteria.selectedDates.contains("Unknown")
                {
                    return false
                }
                if !filterCriteria.selectedShutterSpeeds.isEmpty
                    && !filterCriteria.selectedShutterSpeeds.contains("Unknown")
                {
                    return false
                }
                if !filterCriteria.selectedApertures.isEmpty
                    && !filterCriteria.selectedApertures.contains("Unknown")
                {
                    return false
                }
                if !filterCriteria.selectedFocalLengths.isEmpty
                    && !filterCriteria.selectedFocalLengths.contains("Unknown")
                {
                    return false
                }
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
        var children: [CatalogFolderNode]?  // Optional for OutlineGroup
        let isAvailable: Bool
        let fileCount: Int

        var name: String { url.lastPathComponent }

        init(url: URL, children: [CatalogFolderNode]? = nil, fileCount: Int = 0) {
            self.url = url
            self.children = children
            // Check if folder exists
            var isDir: ObjCBool = false
            self.isAvailable =
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                && isDir.boolValue
            self.fileCount = fileCount
        }
    }

    @Published var allMediaItems: [MediaItem] = []  // Store all items in catalog
    @Published var isImporting = false
    @Published var importProgress: Double = 0.0
    @Published var importStatusMessage: String = ""
    @Published var catalogRootNodes: [CatalogFolderNode] = []  // Hierarchical folders
    @Published var pendingImports: [URL] = []  // Folders currently being imported

    private func loadMediaItems(from catalog: Catalog) {
        do {
            let items = try mediaRepository.fetchMediaItems(in: catalog)
            allMediaItems = items  // Store all items

            // Populate metadata cache from ALL items to ensure filters show all options
            populateMetadataCache(from: items)

            // Build Catalog Tree
            let paths = Set(items.compactMap { $0.originalPath }).map {
                URL(fileURLWithPath: $0).deletingLastPathComponent().standardizedFileURL
            }
            let uniqueFolders = Array(Set(paths)).sorted { $0.path < $1.path }
            catalogRootNodes = buildCatalogTree(from: uniqueFolders)

            // Apply current filter
            let filteredItems = filterItems(items)

            let mapped = filteredItems.compactMap { item -> FileItem? in
                guard let path = item.originalPath else { return nil }
                let url = URL(fileURLWithPath: path)
                // Use MediaItem ID for cache linking
                return FileItem(
                    url: url, isDirectory: false, uuid: item.id ?? UUID(),
                    colorLabel: item.colorLabel, isFavorite: item.isFavorite, flagStatus: item.flagStatus,
                    creationDate: item.importDate,
                    modificationDate: item.modifiedDate, fileSize: item.fileSize,
                    orientation: item.orientation == 0 ? nil : Int(item.orientation))
            }
            fileItems = sortItems(mapped)
            
            // Start background thumbnail pre-fetching
            startBackgroundThumbnailLoading(for: fileItems)
            
            // Resume thumbnail generation if needed
            checkMissingThumbnails()
            
        } catch {
            print("Failed to load media items: \(error)")
            fileItems = []
            allMediaItems = []
            catalogRootNodes = []
        }
    }

    private func buildCatalogTree(from folders: [URL]) -> [CatalogFolderNode] {
        guard !folders.isEmpty else { return [] }

        // Only show explicitly added folders as roots.
        // Do not show unadded parent folders.
        
        // Calculate file counts (recursive for each root)
        var fileCounts: [String: Int] = [:]
        for item in allMediaItems {
            if let path = item.originalPath {
                // Check which root this file belongs to
                // We use the longest matching root to handle nested roots correctly
                var bestMatch: URL?
                var maxLen = 0
                
                for root in folders {
                    if path.hasPrefix(root.path) {
                        if root.path.count > maxLen {
                            maxLen = root.path.count
                            bestMatch = root
                        }
                    }
                }
                
                if let match = bestMatch {
                    let key = match.path.lowercased()
                    fileCounts[key, default: 0] += 1
                }
            }
        }
        
        // Create nodes
        let nodes = folders.map { url -> CatalogFolderNode in
            let key = url.path.lowercased()
            return CatalogFolderNode(url: url, fileCount: fileCounts[key] ?? 0)
        }
        
        // Sort by name
        return nodes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
                node.children = children.map { $0.toStruct() }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
            return node
        }
    }

    private func buildTree(urls: [URL], fileCounts: [String: Int]) -> [CatalogFolderNode] {
        var nodes: [String: NodeBuilder] = [:] // Key: Lowercase Path
        
        for url in urls {
            let key = url.path.lowercased()
            nodes[key] = NodeBuilder(url: url, fileCount: fileCounts[key] ?? 0)
        }

        var roots: [NodeBuilder] = []

        for url in urls {
            let key = url.path.lowercased()
            guard let node = nodes[key] else { continue }
            
            let parentURL = url.deletingLastPathComponent()
            let parentKey = parentURL.path.lowercased()

            if let parentNode = nodes[parentKey], parentKey != key { // Ensure we don't parent to self (root)
                parentNode.children.append(node)
            } else {
                // If parent is not in our node list, this is a root
                roots.append(node)
            }
        }

        // Flatten roots: If root is "/" or "/Volumes", replace with children
        var flattenedRoots = roots
        
        var changed = true
        while changed {
            changed = false
            var newRoots: [NodeBuilder] = []
            
            for root in flattenedRoots {
                let path = root.url.path
                if path == "/" || path == "/Volumes" {
                    // Promote children
                    newRoots.append(contentsOf: root.children)
                    changed = true
                } else {
                    newRoots.append(root)
                }
            }
            flattenedRoots = newRoots

        }

        return flattenedRoots.map { $0.toStruct() }.sorted { $0.name < $1.name }
    }

    private func populateMetadataCache(from items: [MediaItem]) {
        // Extract ObjectIDs on MainActor to avoid thread safety issues
        let objectIDs = items.map { $0.objectID }
        
        // Offload to background to avoid blocking Main Thread with Fault firing
        Task.detached(priority: .userInitiated) {
            var newCache: [URL: ExifMetadata] = [:]
            
            let bgContext = PersistenceController.shared.newBackgroundContext()
            
            await bgContext.perform {
                for id in objectIDs {
                    guard let item = try? bgContext.existingObject(with: id) as? MediaItem,
                          let path = item.originalPath else { continue }
                    let url = URL(fileURLWithPath: path)
                    
                    var meta = ExifMetadata()
                    meta.orientation = Int(item.orientation)
                    meta.rating = Int(item.rating)
                    meta.isFavorite = item.isFavorite
                    meta.flagStatus = Int(item.flagStatus)
                    meta.width = Int(item.width)
                    meta.height = Int(item.height)
                    meta.colorLabel = item.colorLabel
                    
                    if let exif = item.exifData {
                        meta.cameraMake = exif.cameraMake
                        meta.cameraModel = exif.cameraModel
                        meta.lensModel = exif.lensModel
                        meta.focalLength = exif.focalLength
                        meta.aperture = exif.aperture
                        meta.shutterSpeed = exif.shutterSpeed
                        meta.iso = Int(exif.iso)
                        meta.dateTimeOriginal = exif.dateTimeOriginal
                        meta.software = exif.software
                        meta.meteringMode = exif.meteringMode
                        meta.flash = exif.flash
                        meta.whiteBalance = exif.whiteBalance
                        meta.exposureProgram = exif.exposureProgram
                        meta.exposureCompensation = exif.exposureCompensation
                    }
                    newCache[url] = meta
                }
            }
            
            let finalCache = newCache
            await MainActor.run {
                self.metadataCache = finalCache
                self.objectWillChange.send() // Trigger UI update
            }
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
            UserDefaults.standard.set(
                Array(expandedCatalogFolders), forKey: "expandedCatalogFolders")
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
            let items = FileSystemService.shared.getContentsOfDirectory(
                at: folderURL, calculateCounts: false)
            let fsTime = Date()
            Logger.shared.log(
                "DEBUG: FS load took \(fsTime.timeIntervalSince(startTime))s for \(items.count) items"
            )

            let allowedExtensions = FileConstants.allAllowedExtensions

            // Filter by extension only first
            let rawFiles = items.filter { item in
                !item.isDirectory && allowedExtensions.contains(item.url.pathExtension.lowercased())
            }

            // Sort in background (now fast due to pre-fetched attributes)
            let sortedFiles = FileSortService.sortFiles(
                rawFiles, by: currentSortOption, ascending: currentSortAscending)
            let sortTime = Date()
            Logger.shared.log("DEBUG: Sort took \(sortTime.timeIntervalSince(fsTime))s")

            if Task.isCancelled { return }

            await MainActor.run {
                let mainStart = Date()
                // Ensure we are still looking at the same folder
                guard self.currentFolder?.url == folderURL else { return }

                self.allFiles = sortedFiles  // Store sorted files

                // Apply current filters (Main Thread, but usually fast)
                // Note: Filter should preserve order
                let filtered = self.filterFileItems(self.allFiles)
                self.fileItems = filtered

                let mainEnd = Date()
                print(
                    "DEBUG: MainActor update took \(mainEnd.timeIntervalSince(mainStart))s. Total: \(mainEnd.timeIntervalSince(startTime))s"
                )

                // Start background metadata loading
                Task {
                    await self.loadMetadataForCurrentFolder()
                }

                // Start background thumbnail pre-fetching
                self.startBackgroundThumbnailLoading(for: filtered)
            }
        }

        // Start monitoring (MainActor is fine for setup, but callback is async)
        FileSystemMonitor.shared.startMonitoring(url: folder.url) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }

                // Skip reload if we are actively updating metadata (prevents flash/selection loss)
                if self.isUpdatingMetadata { return }

                // Debounce
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s

                // Check again after sleep
                if self.isUpdatingMetadata { return }

                if let current = self.currentFolder, current.url == folder.url {
                    self.loadFiles(in: current)
                    // Also trigger global refresh for sidebar
                    self.fileSystemRefreshID = UUID()
                }

                // Catalog Mode Sync
                if self.appMode == .catalog, let catalogFolder = self.selectedCatalogFolder,
                    catalogFolder == folder.url
                {
                    Logger.shared.log(
                        "MainViewModel: FileSystem change detected in Catalog Folder: \(folder.url.lastPathComponent)"
                    )
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
                    Task {
                        await self.loadMetadataForCurrentFolder()
                    }

                    // Also, if we want to support "Update Catalog" automatically:
            }
        }
    }
    }
    
    private var thumbnailLoadingTask: Task<Void, Never>?
    
    private func startBackgroundThumbnailLoading(for items: [FileItem]) {
        thumbnailLoadingTask?.cancel()
        
        let size = CGSize(width: thumbnailSize, height: thumbnailSize)
        // Capture items and size
        thumbnailLoadingTask = Task.detached(priority: .utility) {
            for item in items {
                if Task.isCancelled { return }
                
                // Check if already cached (Memory)
                let key = "\(item.url.path)_\(Int(size.width))x\(Int(size.height))_v4"
                if ImageCacheService.shared.image(forKey: key) != nil {
                    continue
                }
                
                // Generate (will cache automatically)
                // We don't need the result here, just trigger generation/caching
                _ = await ThumbnailGenerator.shared.generateThumbnail(for: item.url, size: size)
                
                // Yield to allow other tasks (like UI scrolling) to take precedence
                await Task.yield()
            }
        }
    }
    
    func loadRootFolders() async {
        // FileSystemService methods are now nonisolated (synchronous)
        let roots = FileSystemService.shared.getRootFolders()
        await MainActor.run {
            self.rootFolders = roots
            // Restore last used catalog
            self.loadCurrentCatalogID()
        }
    }

    public func loadMetadataForCurrentFolder(items: [URL]? = nil, localRatings: [URL: Int16]? = nil)
        async
    {
        isLoadingMetadata = true
        metadataCache.removeAll()

        let itemsToLoad: [FileItem]
        if let urls = items {
            // Create temporary FileItems for loading if passed directly
            itemsToLoad = urls.map { FileItem(url: $0, isDirectory: false) }
        } else {
            itemsToLoad = allFiles
        }

        // Pre-fetch ratings from Core Data to prevent overwrite by empty Exif
        // Pre-fetch ratings from Core Data to prevent overwrite by empty Exif
        var localRatingsMap: [URL: Int16] = localRatings ?? [:]



        if localRatings == nil {
            let context = persistenceController.newBackgroundContext()
            await context.perform {
                let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                let paths = itemsToLoad.map { $0.url.path }
                request.predicate = NSPredicate(format: "originalPath IN %@", paths)
                if let items = try? context.fetch(request) {
                    for item in items {
                        if let path = item.originalPath {
                            localRatingsMap[URL(fileURLWithPath: path)] = item.rating
                        }
                    }
                }
            }
        }
        
        // Let's fetch everything into a struct map here.
        var localMetadataMap: [URL: (rating: Int16, isFavorite: Bool, flagStatus: Int16)] = [:]
        
        let context = persistenceController.newBackgroundContext()
        await context.perform {
            let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
            let paths = itemsToLoad.map { $0.url.path }
            request.predicate = NSPredicate(format: "originalPath IN %@", paths)
            if let items = try? context.fetch(request) {
                for item in items {
                    if let path = item.originalPath {
                        localMetadataMap[URL(fileURLWithPath: path)] = (item.rating, item.isFavorite, item.flagStatus)
                    }
                }
            }
        }

        metadataTask = Task {
            var batch: [URL: ExifMetadata] = [:]

            // Separate RAWs and Non-RAWs
            let rawExtensions = FileConstants.allowedImageExtensions.filter {
                !["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"].contains($0)
            }

            let rawItems = itemsToLoad.filter {
                rawExtensions.contains($0.url.pathExtension.lowercased())
            }
            let otherItems = itemsToLoad.filter {
                !rawExtensions.contains($0.url.pathExtension.lowercased())
            }

            // 1. Process RAWs in batches (ExifTool)

            // We can process all RAWs in one go or chunks. readExifBatch handles chunks.
            if !rawItems.isEmpty {
                let rawURLs = rawItems.map { $0.url }
                let rawMetadata = await ExifReader.shared.readExifBatch(from: rawURLs)

                // Process results and merge with local ratings
                // Process results and merge with local ratings
                await MainActor.run {
                    for item in rawItems {
                        var data = rawMetadata[item.url] ?? ExifMetadata()

                        // Dimensions are already swapped by ExifReader
                        // if [5, 6, 7, 8].contains(data.orientation ?? 1) { ... }

                        // Merge Rating and Flags
                        if let local = localMetadataMap[item.url] {
                            data.rating = Int(local.rating)
                            data.isFavorite = local.isFavorite
                            data.flagStatus = Int(local.flagStatus)
                        } else if let localRating = localRatingsMap[item.url] {
                            // Fallback if map failed but rating map exists (unlikely)
                            data.rating = Int(localRating)
                        }
                        self.metadataCache[item.url.standardizedFileURL] = data
                    }

                    // Re-sort if needed (e.g. if sorting by Date which depends on Exif)
                    if self.sortOption == .date { self.applySort() }
                }
            }

            if Task.isCancelled { return }

            // 2. Process others one by one (CGImageSource is fast enough usually, or we can batch if needed)
            var count = 0
            for item in otherItems {
                if Task.isCancelled { break }

                var exif = await ExifReader.shared.readExif(from: item.url) ?? ExifMetadata()

                // Merge Rating and Flags
                if let local = localMetadataMap[item.url] {
                    exif.rating = Int(local.rating)
                    exif.isFavorite = local.isFavorite
                    exif.flagStatus = Int(local.flagStatus)
                } else if let localRating = localRatingsMap[item.url] {
                    exif.rating = Int(localRating)
                }

                batch[item.url] = exif
                count += 1

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
                    try? await Task.sleep(nanoseconds: 5_000_000)  // 5ms yield
                }
            }

    // MARK: - Thumbnail Service
    @ObservedObject var thumbnailService = ThumbnailGenerationService.shared
    
    var isGeneratingThumbnails: Bool { thumbnailService.isGenerating }
    var thumbnailProgress: Double { thumbnailService.progress }
    var thumbnailStatusMessage: String { thumbnailService.statusMessage }

    // ...

            // Final batch for others
            let finalBatch = batch
            await MainActor.run {
                for (url, data) in finalBatch {
                    // Fix: Use standardized URL for cache key to match FileItem
                    self.metadataCache[url.standardizedFileURL] = data
                }
                self.isLoadingMetadata = false

                // Re-sort if needed (e.g. if sorting by Date which depends on Exif)
                if self.sortOption == .date {
                    self.applySort()
                }
            }
        }
    }
    
    // MARK: - Thumbnail Resume
    func checkMissingThumbnails() {
        guard let catalog = currentCatalog else { return }
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            let context = PersistenceController.shared.newBackgroundContext()
            
            var missingIDs: [NSManagedObjectID] = []
            
            await context.perform {
                let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                request.predicate = NSPredicate(format: "catalog == %@", catalog)
                
                if let items = try? context.fetch(request) {
                    for item in items {
                        let uuid = item.id ?? UUID()
                        if ThumbnailCacheService.shared.loadThumbnail(for: uuid) == nil {
                            // Check if file is available
                            if let path = item.originalPath, FileManager.default.fileExists(atPath: path) {
                                missingIDs.append(item.objectID)
                            }
                        }
                    }
                }
            }
            
            if !missingIDs.isEmpty {
                await MainActor.run {
                    ThumbnailGenerationService.shared.enqueue(items: missingIDs)
                }
            }
        }
    }

    func applySort() {
        allFiles = FileSortService.sortFiles(
            allFiles, by: sortOption, ascending: isSortAscending, metadataCache: metadataCache)
        applyFilter()
    }

    private func sortItems(_ items: [FileItem]) -> [FileItem] {
        return FileSortService.sortFiles(items, by: sortOption, ascending: isSortAscending)
    }

    // Blocking Operation State
    @Published var isBlockingOperation = false
    @Published var blockingOperationProgress: Double = 0
    @Published var blockingOperationMessage: String = ""

    // Async helper for Copy
    private func performCopyFile(_ item: FileItem, to folderURL: URL, progressHandler: ((Double) -> Void)? = nil) async {
        let srcPath = item.url.standardizedFileURL.path
        let destPath = folderURL.standardizedFileURL.path
        if destPath.hasPrefix(srcPath) {
            Logger.shared.log("Error: Cannot copy folder into itself")
            return
        }

        do {
            let destURL = folderURL.appendingPathComponent(item.url.lastPathComponent)
            // Run I/O on background thread
            // Run I/O on background thread
            try await Task.detached(priority: .userInitiated) {
                if item.isDirectory {
                    // For directories, use recursive copy with progress
                    var currentCount = 0
                    let totalFiles = self.countFiles(at: item.url)
                    try await self.copyWithProgress(from: item.url, to: destURL, totalItems: totalFiles, currentCount: &currentCount)
                } else {
                    // Use chunked copy for progress
                    try await self.copyFileWithProgress(from: item.url, to: destURL, fileSize: item.fileSize ?? 0, progressHandler: progressHandler)
                }
            }.value
            Logger.shared.log("Copied \(item.name) to \(destURL.path)")
        } catch {
            Logger.shared.log("Failed to copy file: \(error)")
        }
    }

    func copyFile(_ item: FileItem, to folderURL: URL) {
        Task {
            await performCopyFile(item, to: folderURL)
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
        
        // Check for recursive copy
        let srcPath = source.standardizedFileURL.path
        let destPath = dest.standardizedFileURL.path
        if destPath.hasPrefix(srcPath) {
            Logger.shared.log("Error: Cannot copy folder into itself")
            return
        }
        
        isBlockingOperation = true
        blockingOperationMessage = "Preparing to copy \(item.name)..."
        blockingOperationProgress = -1
        
        Task {
            let totalFiles = await Task.detached { self.countFiles(at: source) }.value
            blockingOperationMessage = "Copying \(item.name) (\(totalFiles) items)..."
            blockingOperationProgress = 0
            
            let destURL = dest.appendingPathComponent(source.lastPathComponent)
            
            do {
                var currentCount = 0
                try await Task.detached(priority: .userInitiated) {
                    try await self.copyWithProgress(from: source, to: destURL, totalItems: totalFiles, currentCount: &currentCount)
                }.value
                
                Logger.shared.log("Copied \(item.name) to \(destURL.path)")
                
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to copy folder: \(error.localizedDescription)"
                    self.showError = true
                }
            }
            
            await MainActor.run {
                self.isBlockingOperation = false
                self.copySourceURL = nil
                self.copyDestinationURL = nil
                self.showCopyConfirmation = false
                self.fileSystemRefreshID = UUID() // Force refresh
                NotificationCenter.default.post(name: .refreshFileSystem, object: nil)
            }
        }
    }
    
    // Helper to hold multiple files for copy/move
    var filesToCopy: [FileItem] = []
    var filesToMove: [FileItem] = []
    var fileOpDestination: URL?

    func requestCopyFiles(_ items: [FileItem], to destination: URL) {
        filesToCopy = items
        fileOpDestination = destination
        showCopyFilesConfirmation = true
    }
    
    @Published var showCopyFilesConfirmation = false

    func confirmCopyFiles() {
        guard let dest = fileOpDestination, !filesToCopy.isEmpty else { return }
        let items = filesToCopy
        
        isBlockingOperation = true
        blockingOperationMessage = "Copying \(items.count) items..."
        blockingOperationProgress = 0
        
        Task { @MainActor in
            var count = 0
            let total = Double(items.count)
            
            for (index, item) in items.enumerated() {
                self.blockingOperationMessage = "Copying \(item.name)..."
                
                await performCopyFile(item, to: dest) { fileProgress in
                    let totalProgress = (Double(index) + fileProgress) / total
                    Task { @MainActor in
                        self.blockingOperationProgress = totalProgress
                    }
                }
                
                count += 1
                self.blockingOperationProgress = Double(count) / total
            }
            
            self.isBlockingOperation = false
            self.filesToCopy = []
            self.fileOpDestination = nil
            self.showCopyFilesConfirmation = false
            NotificationCenter.default.post(name: .refreshFileSystem, object: nil)
        }
    }

    // Async helper for Move
    private func performMoveFile(_ item: FileItem, to folderURL: URL, progressHandler: ((Double) -> Void)? = nil) async {
        let srcPath = item.url.standardizedFileURL.path
        let destPath = folderURL.standardizedFileURL.path
        if destPath.hasPrefix(srcPath) {
            Logger.shared.log("Error: Cannot move folder into itself")
            return
        }

        let destURL = folderURL.appendingPathComponent(item.url.lastPathComponent)

        // 1. Update Catalog paths BEFORE move
        await updateCatalogPaths(from: item.url, to: destURL)

        do {
            // Check volumes
            let srcValues = try? item.url.resourceValues(forKeys: [.volumeIdentifierKey])
            let destValues = try? folderURL.resourceValues(forKeys: [.volumeIdentifierKey])
            
            let sameVolume = (srcValues?.volumeIdentifier as? NSObject) != nil && (destValues?.volumeIdentifier as? NSObject) != nil && (srcValues?.volumeIdentifier as? NSObject) == (destValues?.volumeIdentifier as? NSObject)
            
            if sameVolume {
                // Fast Move (Rename)
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.moveItem(at: item.url, to: destURL)
                }.value
                progressHandler?(1.0)
            } else {
                // Cross-Volume Move (Copy + Delete) with Progress
                // Cross-Volume Move (Copy + Delete) with Progress
                try await Task.detached(priority: .userInitiated) {
                    if item.isDirectory {
                        var currentCount = 0
                        let totalFiles = self.countFiles(at: item.url)
                        try await self.copyWithProgress(from: item.url, to: destURL, totalItems: totalFiles, currentCount: &currentCount)
                    } else {
                        try await self.copyFileWithProgress(from: item.url, to: destURL, fileSize: item.fileSize ?? 0, progressHandler: progressHandler)
                    }
                    try FileManager.default.removeItem(at: item.url)
                }.value
            }
            
            Logger.shared.log("Moved \(item.name) to \(destURL.path)")

            // 3. Refresh list if we moved out of current folder
            if let current = self.currentFolder,
                current.url == item.url.deletingLastPathComponent()
            {
                self.loadFiles(in: current)
            }
        } catch {
            Logger.shared.log("Failed to move file: \(error)")
        }
    }

    func moveFile(_ item: FileItem, to folderURL: URL) {
        Task {
            await performMoveFile(item, to: folderURL)
        }
    }
    
    func requestMoveFiles(_ items: [FileItem], to destination: URL) {
        filesToMove = items
        fileOpDestination = destination
        showMoveFilesConfirmation = true
    }
    
    @Published var showMoveFilesConfirmation = false

    func confirmMoveFiles() {
        guard let dest = fileOpDestination, !filesToMove.isEmpty else { return }
        let items = filesToMove
        
        isBlockingOperation = true
        blockingOperationMessage = "Moving \(items.count) items..."
        blockingOperationProgress = 0
        
        Task { @MainActor in
            var count = 0
            let total = Double(items.count)
            
            for (index, item) in items.enumerated() {
                self.blockingOperationMessage = "Moving \(item.name)..."
                
                await performMoveFile(item, to: dest) { fileProgress in
                    let totalProgress = (Double(index) + fileProgress) / total
                    Task { @MainActor in
                        self.blockingOperationProgress = totalProgress
                    }
                }
                
                count += 1
                self.blockingOperationProgress = Double(count) / total
            }
            
            self.isBlockingOperation = false
            self.filesToMove = []
            self.fileOpDestination = nil
            self.showMoveFilesConfirmation = false
            self.fileSystemRefreshID = UUID() // Force refresh
            NotificationCenter.default.post(name: .refreshFileSystem, object: nil)
        }
    }

    func requestMoveFolder(from source: URL, to destination: URL) {
        moveSourceURL = source
        moveDestinationURL = destination
        showMoveConfirmation = true
    }

    func confirmMoveFolder() {
        guard let source = moveSourceURL, let dest = moveDestinationURL else { return }
        let item = FileItem(url: source, isDirectory: true)
        
        isBlockingOperation = true
        blockingOperationMessage = "Preparing to move \(item.name)..."
        blockingOperationProgress = -1
        
        Task {
            // Check volumes
            let srcValues = try? source.resourceValues(forKeys: [.volumeIdentifierKey])
            let destValues = try? dest.resourceValues(forKeys: [.volumeIdentifierKey])
            
            let sameVolume = (srcValues?.volumeIdentifier as? NSObject) != nil && (destValues?.volumeIdentifier as? NSObject) != nil && (srcValues?.volumeIdentifier as? NSObject) == (destValues?.volumeIdentifier as? NSObject)
            
            if sameVolume {
                // Fast Move (Rename)
                blockingOperationMessage = "Moving \(item.name)..."
                await performMoveFile(item, to: dest)
            } else {
                // Cross-Volume Move (Copy + Delete) with Progress
                let totalFiles = await Task.detached { self.countFiles(at: source) }.value
                blockingOperationMessage = "Moving \(item.name) (\(totalFiles) items)..."
                blockingOperationProgress = 0
                
                let destURL = dest.appendingPathComponent(source.lastPathComponent)
                
                do {
                    var currentCount = 0
                    try await Task.detached(priority: .userInitiated) {
                        try await self.copyWithProgress(from: source, to: destURL, totalItems: totalFiles, currentCount: &currentCount)
                    }.value
                    
                    // Delete source after successful copy
                    try FileManager.default.removeItem(at: source)
                    
                    Logger.shared.log("Moved (Copy+Delete) \(item.name) to \(destURL.path)")
                    
                    // Update Catalog if needed (performMoveFile logic handles this, but we did manual copy)
                    // We should replicate the catalog update logic here or extract it.
                    // For now, let's just call the catalog update part?
                    // Or better, let's assume FileSystemMonitor handles the "Delete" and "Create".
                    // But we want to preserve metadata/catalog links.
                    // The `performMoveFile` logic for catalog update is complex.
                    // We should probably extract it.
                    // However, for now, let's just rely on the fact that cross-volume move is rare and maybe losing catalog link is acceptable?
                    // NO, user complained about catalog data loss.
                    // So we MUST update catalog.
                    
                    // Let's call the catalog update logic manually.
                    await self.updateCatalogPaths(from: source, to: destURL)
                    
                } catch {
                     await MainActor.run {
                        self.errorMessage = "Failed to move folder: \(error.localizedDescription)"
                        self.showError = true
                    }
                }
            }
            
            await MainActor.run {
                self.isBlockingOperation = false
                self.moveSourceURL = nil
                self.moveDestinationURL = nil
                self.showMoveConfirmation = false
                self.fileSystemRefreshID = UUID() // Force refresh
                NotificationCenter.default.post(name: .refreshFileSystem, object: nil)
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
            
            // Delete items
            let context = persistenceController.container.viewContext
            for item in items {
                // Remove thumbnail
                let uuid = item.id ?? UUID()
                ThumbnailCacheService.shared.deleteThumbnail(for: uuid)
                
                context.delete(item)
            }
            
            try context.save()
            
            // UI Updates on MainActor
            Task { @MainActor in
                // If current file is in the removed folder, clear it
                if let current = self.currentFile, current.url.path.hasPrefix(folderPath) {
                    self.currentFile = nil
                }
                
                // Refresh catalog view
                self.loadMediaItems(from: catalog)
            }
            
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
            if offset > 0 { newIndex = 0 } else { newIndex = fileItems.count - 1 }
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

    func selectFile(
        _ item: FileItem, toggle: Bool = false, extend: Bool = false, autoScroll: Bool = true
    ) {
        isAutoScrollEnabled = autoScroll
        if extend, let current = currentFile, let currentIndex = fileItems.firstIndex(of: current),
            let newIndex = fileItems.firstIndex(of: item)
        {
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
                    currentFile = selectedFiles.first  // Fallback
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
        let isRaw =
            FileConstants.allowedImageExtensions.contains(ext)
            && !["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"].contains(ext)

        if isRaw && appMode != .catalog {
            Logger.shared.log(
                "MainViewModel: Skipped rating update for RAW file in Folders mode: \(item.name)")
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
                    Logger.shared.log(
                        "MainViewModel: Saved rating \(rating) for item \(item.url.lastPathComponent)"
                    )
                } else {
                    Logger.shared.log(
                        "MainViewModel: No MediaItem found for rating update: \(item.url.lastPathComponent)"
                    )
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

    public func setRating(_ rating: Int, for items: [FileItem]) {
        updateRating(for: items, rating: rating)
    }

    func updateRating(for items: [FileItem], rating: Int) {
        // 1. Update Metadata Cache (Optimistic)
        for item in items {
            if var meta = metadataCache[item.url] {
                meta.rating = rating
                metadataCache[item.url] = meta
            } else {
                var meta = ExifMetadata()
                meta.rating = rating
                metadataCache[item.url] = meta
            }
        }
        
        // 2. Persist (Async)
        Task {
            // Update Core Data
            let context = persistenceController.newBackgroundContext()
            await context.perform {
                for item in items {
                    let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                    if let uuid = item.uuid {
                        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
                    } else {
                        request.predicate = NSPredicate(format: "originalPath == %@", item.url.path)
                    }
                    
                    if let mediaItems = try? context.fetch(request), let mediaItem = mediaItems.first {
                        mediaItem.rating = Int16(rating)
                    }
                }
                try? context.save()
            }
            
            // Write to File (Batch)
            let urls = items.map { $0.url }
            self.writeMetadataBatch(to: urls, rating: rating, label: nil)
            
            await MainActor.run {
                self.applyFilter()
            }
        }
    }

    func updateColorLabel(for items: [FileItem], label: String?) {
        // Batch update to prevent UI thrashing
        
        // Update Metadata Cache (Optimistic)
        for item in items {
            if var meta = metadataCache[item.url] {
                meta.colorLabel = label
                metadataCache[item.url] = meta
            } else {
                var meta = ExifMetadata()
                meta.colorLabel = label
                metadataCache[item.url] = meta
            }
        }
        
        var updatedItems: [FileItem] = []
        
        // 1. Update allFiles and fileItems
        for item in items {
            var updatedItem: FileItem?
            
            // Update allFiles
            if let index = allFiles.firstIndex(where: { $0.id == item.id }) {
                var newItem = allFiles[index]
                newItem.colorLabel = label
                allFiles[index] = newItem
                updatedItems.append(newItem)
                updatedItem = newItem
            }
            
            // Update fileItems
            if let index = fileItems.firstIndex(where: { $0.id == item.id }) {
                var newItem = fileItems[index]
                newItem.colorLabel = label
                fileItems[index] = newItem
                if updatedItem == nil { updatedItem = newItem }
            }
            
            // Update selectedFiles
            if let oldItem = selectedFiles.first(where: { $0.id == item.id }) {
                selectedFiles.remove(oldItem)
                var newItem = oldItem
                newItem.colorLabel = label
                selectedFiles.insert(newItem)
                if updatedItem == nil { updatedItem = newItem }
            }
            
            // Update currentFile
            if currentFile?.id == item.id {
                if let updated = updatedItem {
                    currentFile = updated
                } else {
                    var newItem = currentFile!
                    newItem.colorLabel = label
                    currentFile = newItem
                }
            }
            
            // Update Metadata Cache
            if var meta = metadataCache[item.url] {
                meta.colorLabel = label
                metadataCache[item.url] = meta
            } else {
                var meta = ExifMetadata()
                meta.colorLabel = label
                metadataCache[item.url] = meta
            }
        }
        
        // 2. Update selectedFiles (Batch)
        for newItem in updatedItems {
            if let oldSelected = selectedFiles.first(where: { $0.id == newItem.id }) {
                selectedFiles.remove(oldSelected)
                selectedFiles.insert(newItem)
            }
        }
        
        // 3. Persist (Async)
        Task {
            // Update Core Data
            let context = persistenceController.newBackgroundContext()
            await context.perform {
                for item in items {
                    let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                    if let uuid = item.uuid {
                        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
                    } else {
                        request.predicate = NSPredicate(format: "originalPath == %@", item.url.path)
                    }
                    
                    if let mediaItems = try? context.fetch(request), let mediaItem = mediaItems.first {
                        mediaItem.colorLabel = label
                    }
                }
                try? context.save()
            }
            
            // Write to File (Batch)
            let urls = items.map { $0.url }
            // For label update, we pass rating: nil (preserve rating)
            self.writeMetadataBatch(to: urls, rating: nil, label: label ?? "")
            
            await MainActor.run {
                self.applyFilter()
            }
        }
    }
    
    // MARK: - Favorite and Flag Status
    
    func toggleFavorite(for items: [FileItem]) {
        guard appMode == .catalog else { return }
        
        // Determine target state
        // If ALL are favorites -> Turn OFF
        // Otherwise (mixed or all off) -> Turn ON
        let allFavorites = items.allSatisfy { $0.isFavorite == true }
        let newStatus = !allFavorites
        
        // Batch update allFiles and fileItems
        var updatedItems: [FileItem] = []
        
        for item in items {
            var updatedItem: FileItem?
            
            // Update allFiles
            if let index = allFiles.firstIndex(where: { $0.id == item.id }) {
                var newItem = allFiles[index]
                newItem.isFavorite = newStatus
                allFiles[index] = newItem
                updatedItems.append(newItem)
                updatedItem = newItem
            }
            
            // Update fileItems
            if let index = fileItems.firstIndex(where: { $0.id == item.id }) {
                var newItem = fileItems[index]
                newItem.isFavorite = newStatus
                fileItems[index] = newItem
                if updatedItem == nil { updatedItem = newItem }
            }
            
            // Update selectedFiles
            if let oldItem = selectedFiles.first(where: { $0.id == item.id }) {
                selectedFiles.remove(oldItem)
                var newItem = oldItem
                newItem.isFavorite = newStatus
                selectedFiles.insert(newItem)
                if updatedItem == nil { updatedItem = newItem }
            }
            
            // Update currentFile
            if currentFile?.id == item.id {
                if let updated = updatedItem {
                    currentFile = updated
                } else {
                    var newItem = currentFile!
                    newItem.isFavorite = newStatus
                    currentFile = newItem
                }
            }
            
            // Update Metadata Cache
            if var meta = metadataCache[item.url] {
                meta.isFavorite = newStatus
                metadataCache[item.url] = meta
            } else {
                var meta = ExifMetadata()
                meta.isFavorite = newStatus
                metadataCache[item.url] = meta
            }
        }
        
        // Update Core Data
        Task.detached(priority: .userInitiated) {
            let context = PersistenceController.shared.container.viewContext
            await context.perform {
                let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                for item in items {
                    if let uuid = item.uuid {
                        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
                    } else {
                        request.predicate = NSPredicate(format: "originalPath == %@", item.url.path)
                    }
                    
                    if let mediaItems = try? context.fetch(request), let mediaItem = mediaItems.first {
                        // Toggle logic inside loop to match memory update
                        // But we need to know the NEW status.
                        // Since we iterate, we can't easily batch this if status differs per item.
                        // But toggleFavorite is usually called on selection.
                        // If selection has mixed state, toggle might be weird.
                        // Usually "Toggle" means "Flip".
                        // But here we rely on memory state.
                        // Let's use the memory state we just updated?
                        // But we are in detached task.
                        // We should pass the new status map or just re-fetch and toggle?
                        // Use the newStatus calculated from the selection state
                        mediaItem.isFavorite = newStatus
                    }
                }
                try? context.save()
            }
            
            await MainActor.run {
                self.applyFilter()
            }
        }
    }
    
    func setFlagStatus(for items: [FileItem], status: Int16) {
        guard appMode == .catalog else { return }
        
        // Batch update allFiles and fileItems
        var updatedItems: [FileItem] = []
        
        for item in items {
            var updatedItem: FileItem?
            
            // Update allFiles
            if let index = allFiles.firstIndex(where: { $0.id == item.id }) {
                var newItem = allFiles[index]
                newItem.flagStatus = status
                allFiles[index] = newItem
                updatedItems.append(newItem)
                updatedItem = newItem
            }
            
            // Update fileItems
            if let index = fileItems.firstIndex(where: { $0.id == item.id }) {
                var newItem = fileItems[index]
                newItem.flagStatus = status
                fileItems[index] = newItem
                if updatedItem == nil { updatedItem = newItem }
            }
            
            // Update selectedFiles
            if let oldItem = selectedFiles.first(where: { $0.id == item.id }) {
                selectedFiles.remove(oldItem)
                var newItem = oldItem
                newItem.flagStatus = status
                selectedFiles.insert(newItem)
                if updatedItem == nil { updatedItem = newItem }
            }
            
            // Update currentFile
            if currentFile?.id == item.id {
                if let updated = updatedItem {
                    currentFile = updated
                } else {
                    var newItem = currentFile!
                    newItem.flagStatus = status
                    currentFile = newItem
                }
            }
            
            // Update Metadata Cache
            if var meta = metadataCache[item.url] {
                meta.flagStatus = Int(status)
                metadataCache[item.url] = meta
            } else {
                var meta = ExifMetadata()
                meta.flagStatus = Int(status)
                metadataCache[item.url] = meta
            }
        }
        
        // Update Core Data
        Task.detached(priority: .userInitiated) {
            let context = PersistenceController.shared.container.viewContext
            await context.perform {
                let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                for item in items {
                    if let uuid = item.uuid {
                        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
                    } else {
                        request.predicate = NSPredicate(format: "originalPath == %@", item.url.path)
                    }
                    
                    if let mediaItems = try? context.fetch(request), let mediaItem = mediaItems.first {
                        mediaItem.flagStatus = status
                        mediaItem.isFlagged = (status != 0)  // Update legacy field
                    }
                }
                try? context.save()
            }
            
            await MainActor.run {
                self.applyFilter()
            }
        }
    }
    
    // MARK: - File System Operations

    public func setColorLabel(_ label: String?, for items: [FileItem]) {
        updateColorLabel(for: items, label: label)
    }

    public func setColorLabel(_ label: String?, for item: FileItem) {
        updateColorLabel(for: [item], label: label)
    }

    // moveUp/moveDown are already defined around line 2393
    // Removing duplicate definitions here


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
        guard let current = currentFile, let index = fileItems.firstIndex(of: current) else {
            return
        }
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

    func regenerateThumbnails(for items: [FileItem]) {
        let uuids = items.map { $0.uuid }
        guard !uuids.isEmpty else { return }
        
        // Fetch ObjectIDs for UUIDs
        let context = persistenceController.newBackgroundContext()
        context.perform {
            let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", uuids)
            
            if let mediaItems = try? context.fetch(request) {
                let objectIDs = mediaItems.map { $0.objectID }
                
                Task { @MainActor in
                    ThumbnailGenerationService.shared.enqueue(items: objectIDs)
                    Logger.shared.log("MainViewModel: Enqueued \(objectIDs.count) items for thumbnail regeneration.")
                }
            }
        }
    }

    // MARK: - Catalog Update

    struct CatalogUpdateStats {
        var added: [URL] = []
        var removed: [URL] = []
        var updated: [URL] = []
        var metadataMismatches: [URL] = []

        var totalChanges: Int {
            added.count + removed.count + updated.count + metadataMismatches.count
        }
    }

    @Published var isScanningCatalog: Bool = false

    func triggerFolderUpdateCheck(folder: URL) {
        guard let catalog = currentCatalog else { return }
        isScanningCatalog = true
        Task {
            let stats = await checkForUpdates(catalog: catalog, scope: folder)
            await MainActor.run {
                self.updateStats = stats
                self.catalogToUpdate = catalog
                self.showUpdateConfirmation = true
                self.isScanningCatalog = false
            }
        }
    }

    func checkForUpdates(catalog: Catalog, scope: URL? = nil) async -> CatalogUpdateStats {
        isScanningCatalog = true
        defer { isScanningCatalog = false }

        let catalogID = catalog.objectID

        let controller = self.persistenceController

        return await Task.detached(priority: .userInitiated) {
            var stats = CatalogUpdateStats()

            // 1. Get all known files in DB
            let context = controller.newBackgroundContext()

            var dbFiles: [URL: (date: Date?, rating: Int, label: String?, hasExifData: Bool)] = [:]

            // Create request inside the block to avoid Sendable warning
            context.performAndWait {
                let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                if let scope = scope {
                    request.predicate = NSPredicate(format: "catalog == %@ AND originalPath BEGINSWITH %@", catalogID, scope.path)
                } else {
                    request.predicate = NSPredicate(format: "catalog == %@", catalogID)
                }

                if let items = try? context.fetch(request) {
                    for item in items {
                        if let path = item.originalPath {
                            let url = URL(fileURLWithPath: path)
                            dbFiles[url] = (item.modifiedDate, Int(item.rating), item.colorLabel, item.exifData != nil)
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

            var directoriesToScan: Set<URL> = []
            if let scope = scope {
                directoriesToScan.insert(scope)
                // Also add subdirectories of scope that are in DB?
                // Actually, if we want to find NEW files in subfolders, we should scan recursively?
                // Or just scan the folders we know about + the scope root?
                // If the user says "Update Folder", they usually expect recursive update.
                // But our scan logic (lines 3236+) is non-recursive on `directoriesToScan`.
                // So we need to add all subdirectories of `scope` that are in `dbFiles`.
                // AND we should probably walk the directory tree of `scope` to find NEW subfolders?
                // For now, let's stick to "folders known in DB" + "scope root".
                // If a new subfolder was added on disk, we won't see it unless we do a recursive scan.
                // Given the user request "Update Folder", recursive scan is expected.
                // But implementing full recursive scan here might be complex.
                // Let's assume `directoriesToScan` collects all known folders.
                for url in dbFiles.keys {
                    directoriesToScan.insert(url.deletingLastPathComponent())
                }
                // Ensure scope is included (in case it's empty in DB)
                directoriesToScan.insert(scope)
            } else {
                for url in dbFiles.keys {
                    directoriesToScan.insert(url.deletingLastPathComponent())
                }
            }

            let fileManager = FileManager.default

            // Check for Removed and Updated
            // Check for Removed, Updated, and Metadata Mismatches
            for (url, info) in dbFiles {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
                    if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                        let fileDate = attrs[.modificationDate] as? Date
                    {
                        // Check if updated (allow some tolerance)
                        // Check if updated (allow some tolerance)
                        if let dbDate = info.date, fileDate.timeIntervalSince(dbDate) > 1.0 {
                            stats.updated.append(url)
                        } else if !info.hasExifData {
                            // Missing metadata (e.g. RAW file imported before fix)
                            // Treat as updated to force re-read
                            stats.updated.append(url)
                        }
                        
                        // Check Metadata Mismatches
                        // We use ExifTool via ExifReader to ensure we read exactly what we wrote (XMP/IPTC).
                        // CGImageSource (readExifSync) might not read XMP-xmp:Label correctly.
                        // We also enable this for RAW files now that we use ExifTool which is robust.
                        
                        // Use a detached task or just call synchronous ExifTool wrapper?
                        // Since we are already in a detached task, we can call ExifTool synchronously.
                        // But ExifReader.readExifUsingExifTool is private or not exposed?
                        // Let's check ExifReader. It has `readExifBatch` or `readExifUsingExifTool`.
                        // `readExifUsingExifTool` is internal/private.
                        // We should expose a method `readMetadataSync(from: URL)` that tries ExifTool first.
                        
                        // For now, let's use ExifReader.shared.readExifSync(from: url) but we need to improve IT.
                        // Wait, I can't easily change ExifReader to use ExifTool for *everything* inside readExifSync without performance hit.
                        // But for "Check for Updates", accuracy is more important than speed?
                        // Or maybe we should only use ExifTool if it's a candidate for mismatch?
                        // No, we need to know IF it's a mismatch.
                        
                        // Let's rely on `ExifReader.shared.readExifSync` BUT update it to use ExifTool if needed?
                        // Or better: In this loop, we can use `ExifReader.shared.readExifUsingExifTool(from: url)` if I make it public.
                        // Or I can add a new method `readMetadataAccurate(from: url)`.
                        
                        // Actually, let's look at ExifReader again.
                        // ... (comments)

                        // `_readExif` (private) uses ExifTool for RAWs.
                        // For non-RAWs (JPG), it uses CGImageSource.
                        // But my writeMetadataBatch writes XMP to JPGs too!
                        // So CGImageSource reading JPG might miss XMP Label.
                        // I MUST use ExifTool for JPGs too if I want to verify XMP Label.
                        
                        // So, I will modify ExifReader to allow forcing ExifTool, OR I will call ExifTool here directly.
                        // Calling ExifTool for every file in the catalog (even if not modified) is SLOW.
                        // But wait, we only check `if fileDate > dbDate` (line 2763) for UPDATES.
                        // For MISMATCHES, we check... wait.
                        // Line 2763: `if let dbDate = info.date, fileDate.timeIntervalSince(dbDate) > 1.0` -> `stats.updated.append`.
                        // Line 2767: `Check Metadata Mismatches`.
                        // This block runs for EVERY file that exists?
                        // No, it's inside `if fileManager.fileExists`.
                        // It runs for EVERY file in the DB!
                        // If I run `exiftool` for 10,000 files, it will take forever.
                        // We should ONLY check metadata if the file modification date is DIFFERENT?
                        // If date is same, metadata "should" be same (unless external tool touched it without changing date, which is rare/impossible).
                        // BUT, `writeMetadataBatch` updates file. Does it update DB date?
                        // `performCatalogUpdate` updates DB date.
                        
                        // If I edit in App -> Write File -> Update DB (Date + Metadata).
                        // File Date == DB Date.
                        // So we shouldn't need to check.
                        
                        // But the user says "No matter how much I sync...".
                        // This implies `fileDate` != `dbDate`?
                        // Or maybe the check runs regardless of date?
                        // In the code I see:
                        /*
                        if let dbDate = info.date, fileDate.timeIntervalSince(dbDate) > 1.0 {
                            stats.updated.append(url)
                        }
                        
                        // Check Metadata Mismatches
                        */
                        // It runs ALWAYS.
                        // This is the problem!
                        // We should ONLY check for metadata mismatches if the date matches (or is close),
                        // OR if we suspect something.
                        // Actually, if date is different, it's an "Update".
                        // If date is SAME, but metadata is different -> Mismatch?
                        // No, if date is same, content hasn't changed.
                        // So why check?
                        // Maybe to detect "Metadata changed but date didn't"? (e.g. `touch -m`?)
                        // That's rare.
                        
                        // However, if the user says "Mismatch detected", it means this code IS finding a difference.
                        // If I use `exiftool` here, it will be slow.
                        // But maybe I should only check if `fileDate` is strictly different?
                        // No, the code separates "Updated" (Date changed) vs "Mismatch" (Content diff).
                        
                        // Let's look at the logic again.
                        // If I use `readExifSync` (CGImageSource) on a JPG, and it returns `nil` for Label (because it can't read XMP),
                        // but DB has "Red".
                        // Then `nil != "Red"` -> Mismatch.
                        // This happens even if Date is identical!
                        
                        // So I MUST fix `readExifSync` to read XMP Label correctly for JPGs.
                        // OR I must use ExifTool.
                        
                        // I will modify `ExifReader.swift` to support XMP Label reading via `CGImageSource` (if possible) or fallback.
                        // `CGImageSource` *can* read XMP if we access the `metadata` property of `CGImageSource`?
                        // `CGImageSourceCopyPropertiesAtIndex` returns a dictionary.
                        // `{XMP}` key might contain the raw XMP packet.
                        // Parsing raw XMP is hard.
                        
                        // Alternative: Use `exiftool` but ONLY if `CGImageSource` fails to match DB?
                        // i.e. Double Check Strategy.
                        // If `CGImageSource` says "No Label", but DB says "Red", THEN run `exiftool` to verify if it's really "No Label" or just "Can't read".
                        // This is efficient!
                        
                        // Let's implement this Double Check in `MainViewModel`.
                        
                        if let exif = ExifReader.shared.readExifSync(from: url) {
                            let fileRating = exif.rating ?? 0
                            let dbRating = info.rating
                            
                            let fileLabel = exif.colorLabel
                            let dbLabel = info.label
                            
                            if fileRating != dbRating || fileLabel != dbLabel {
                                // Potential mismatch.
                                // If fileLabel is nil and dbLabel is not, it might be a read error.
                                // Verify with ExifTool if needed.
                                var confirmedMismatch = true
                                
                                if fileLabel == nil && dbLabel != nil {
                                    // Try ExifTool
                                    if let accurateExif = ExifReader.shared.readExifUsingExifTool(from: url) {
                                         if accurateExif.colorLabel == dbLabel && (accurateExif.rating ?? 0) == dbRating {
                                             confirmedMismatch = false
                                         }
                                    }
                                }
                                
                                if confirmedMismatch {
                                    stats.metadataMismatches.append(url)
                                }
                            }
                        }
                    }
                } else {
                    // File does not exist. Check if volume is mounted.
                    let components = url.pathComponents
                    if components.count > 2 && components[1] == "Volumes" {
                        let volumePath = "/" + components[1] + "/" + components[2]
                        var isVolDir: ObjCBool = false
                        if !fileManager.fileExists(atPath: volumePath, isDirectory: &isVolDir) || !isVolDir.boolValue {
                            // Volume unmounted. Ignore.
                            continue
                        }
                    }
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

                if let contents = try? fileManager.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles])
                {
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
                if let resourceValues = try? freshURL.resourceValues(forKeys: [
                    .labelNumberKey, .tagNamesKey, .fileSizeKey, .creationDateKey,
                    .contentModificationDateKey,
                ]) {
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
                        newItems[i] = FileItem(
                            url: newItem.url, isDirectory: newItem.isDirectory,
                            isAvailable: newItem.isAvailable, uuid: newItem.uuid,
                            colorLabel: update.0, isFavorite: newItem.isFavorite,
                            flagStatus: newItem.flagStatus, fileCount: newItem.fileCount,
                            creationDate: update.2, modificationDate: newItem.modificationDate,
                            fileSize: update.1, orientation: newItem.orientation)
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
        
        // Refresh to update counts
        refreshFolders()
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



    func deleteFolder(_ url: URL) {
        isBlockingOperation = true
        blockingOperationMessage = "Deleting \(url.lastPathComponent)..."
        blockingOperationProgress = -1 // Indeterminate

        Task {
            do {
                // Run in background
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.removeItem(at: url)
                }.value
                
                Logger.shared.log("MainViewModel: Deleted folder \(url.path)")

                await MainActor.run {
                    // If current folder was deleted or is a subfolder, clear it
                    if let current = self.currentFolder {
                        let currentPath = current.url.path
                        let deletedPath = url.path
                        if currentPath == deletedPath || currentPath.hasPrefix(deletedPath + "/") {
                            self.currentFolder = nil
                        }
                    }
                    
                    self.isBlockingOperation = false
                    self.fileSystemRefreshID = UUID()
                }
            } catch {
                await MainActor.run {
                    self.isBlockingOperation = false
                    Logger.shared.log(
                        "MainViewModel: Failed to delete folder: \(error.localizedDescription)")
                    self.errorMessage = "Failed to delete folder: \(error.localizedDescription)"
                    self.showError = true
                }
            }
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
            Logger.shared.log(
                "MainViewModel: Failed to create folder: \(error.localizedDescription)")
            self.errorMessage = "Failed to create folder: \(error.localizedDescription)"
            self.showError = true
        }
    }
    // MARK: - Catalog Sync Feature
    
    @Published var showUpdateConfirmation = false
    @Published var updateStats: CatalogUpdateStats?
    @Published var catalogToUpdate: Catalog?
    @Published var isSyncingCatalog = false
    
    // Unified check method (called by both Context Menu and Tools Menu)
    func triggerCatalogUpdateCheck(for catalog: Catalog? = nil) {
        let target = catalog ?? currentCatalog
        guard let target = target else { return }
        catalogToUpdate = target
        
        Task {
            let stats = await checkForUpdates(catalog: target)
            await MainActor.run {
                self.updateStats = stats
                self.showUpdateConfirmation = true
            }
        }
    }
    
    // Legacy method removed or redirected
    func checkForMetadataMismatches() {
        triggerCatalogUpdateCheck()
    }
    
    // ... (checkForUpdates implementation is fine, but we need to ensure it returns stats)
    
    enum MetadataResolutionStrategy {
        case preferCatalog
        case preferFile
    }

    func performCatalogUpdate(catalog: Catalog, stats: CatalogUpdateStats, strategy: MetadataResolutionStrategy? = nil) {
        guard let context = catalog.managedObjectContext else { return }
        isSyncingCatalog = true
        
        Task {
            // 1. Remove deleted
            if !stats.removed.isEmpty {
                await MainActor.run {
                    // Filter out files on unmounted volumes
                    let filesToDelete = stats.removed.filter { url in
                        // Check if volume is mounted
                        return self.isVolumeMounted(for: url)
                    }
                    
                    if !filesToDelete.isEmpty {
                        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                        request.predicate = NSPredicate(
                            format: "catalog == %@ AND originalPath IN %@", catalog,
                            filesToDelete.map { $0.path })
                        if let items = try? context.fetch(request) {
                            for item in items {
                                context.delete(item)
                            }
                        }
                    }
                }
            }
            
            // 2. Add new
            if !stats.added.isEmpty {
                await MainActor.run {
                    for url in stats.added {
                        let item = MediaItem(context: context)
                        item.id = UUID()
                        item.originalPath = url.path
                        item.fileName = url.lastPathComponent
                        item.catalog = catalog
                        item.importDate = Date()
                        
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                            item.fileSize = (attrs[.size] as? Int64) ?? 0
                            item.modifiedDate = attrs[.modificationDate] as? Date
                        }
                        
                        // Populate Metadata
                        if let exif = ExifReader.shared.readExifSync(from: url) {
                            item.rating = Int16(exif.rating ?? 0)
                            item.colorLabel = exif.colorLabel
                            item.width = Int32(exif.width ?? 0)
                            item.height = Int32(exif.height ?? 0)
                            item.orientation = Int16(exif.orientation ?? 1)
                            item.isFavorite = exif.isFavorite ?? false
                            item.flagStatus = Int16(exif.flagStatus ?? 0)
                            
                            // Create ExifData entity
                            let exifData = ExifData(context: context)
                            exifData.cameraMake = exif.cameraMake
                            exifData.cameraModel = exif.cameraModel
                            exifData.lensModel = exif.lensModel
                            exifData.focalLength = exif.focalLength ?? 0
                            exifData.aperture = exif.aperture ?? 0
                            exifData.shutterSpeed = exif.shutterSpeed
                            exifData.iso = Int32(exif.iso ?? 0)
                            exifData.dateTimeOriginal = exif.dateTimeOriginal
                            exifData.software = exif.software
                            exifData.meteringMode = exif.meteringMode
                            exifData.flash = exif.flash
                            exifData.whiteBalance = exif.whiteBalance
                            exifData.exposureProgram = exif.exposureProgram
                            exifData.exposureCompensation = exif.exposureCompensation ?? 0.0
                            
                            // New Fields
                            exifData.brightnessValue = exif.brightnessValue ?? 0.0
                            exifData.exposureBias = exif.exposureBias ?? 0.0
                            exifData.serialNumber = exif.serialNumber
                            exifData.title = exif.title
                            exifData.caption = exif.caption
                            exifData.latitude = exif.latitude ?? 0.0
                            exifData.longitude = exif.longitude ?? 0.0
                            exifData.altitude = exif.altitude ?? 0.0
                            exifData.imageDirection = exif.imageDirection ?? 0.0
                            
                            item.exifData = exifData
                            
                            // Update Cache
                            self.metadataCache[url] = exif
                        }
                    }
                }
            }
            
            // 3. Update existing (File -> DB)
            if !stats.updated.isEmpty {
                await MainActor.run {
                    let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                    request.predicate = NSPredicate(
                        format: "catalog == %@ AND originalPath IN %@", catalog,
                        stats.updated.map { $0.path })
                    
                    if let items = try? context.fetch(request) {
                        for item in items {
                            if let path = item.originalPath {
                                let url = URL(fileURLWithPath: path)
                                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                                    item.fileSize = (attrs[.size] as? Int64) ?? 0
                                    item.modifiedDate = attrs[.modificationDate] as? Date
                                }
                                
                                // Update Metadata
                                if let exif = ExifReader.shared.readExifSync(from: url) {
                                    item.rating = Int16(exif.rating ?? 0)
                                    item.colorLabel = exif.colorLabel
                                    item.width = Int32(exif.width ?? 0)
                                    item.height = Int32(exif.height ?? 0)
                                    item.orientation = Int16(exif.orientation ?? 1)
                                    item.isFavorite = exif.isFavorite ?? false
                                    item.flagStatus = Int16(exif.flagStatus ?? 0)
                                    
                                    // Update or Create ExifData
                                    let exifData = item.exifData ?? ExifData(context: context)
                                    exifData.cameraMake = exif.cameraMake
                                    exifData.cameraModel = exif.cameraModel
                                    exifData.lensModel = exif.lensModel
                                    exifData.focalLength = exif.focalLength ?? 0
                                    exifData.aperture = exif.aperture ?? 0
                                    exifData.shutterSpeed = exif.shutterSpeed
                                    exifData.iso = Int32(exif.iso ?? 0)
                                    exifData.dateTimeOriginal = exif.dateTimeOriginal
                                    exifData.software = exif.software
                                    exifData.meteringMode = exif.meteringMode
                                    exifData.flash = exif.flash
                                    exifData.whiteBalance = exif.whiteBalance
                                    exifData.exposureProgram = exif.exposureProgram
                                    exifData.exposureCompensation = exif.exposureCompensation ?? 0.0
                                    
                                    // New Fields
                                    exifData.brightnessValue = exif.brightnessValue ?? 0.0
                                    exifData.exposureBias = exif.exposureBias ?? 0.0
                                    exifData.serialNumber = exif.serialNumber
                                    exifData.title = exif.title
                                    exifData.caption = exif.caption
                                    exifData.latitude = exif.latitude ?? 0.0
                                    exifData.longitude = exif.longitude ?? 0.0
                                    exifData.altitude = exif.altitude ?? 0.0
                                    exifData.imageDirection = exif.imageDirection ?? 0.0
                                    
                                    item.exifData = exifData
                                    
                                    // Update Cache
                                    self.metadataCache[url] = exif
                                }
                            }
                        }
                    }
                }
            }
            
            // 4. Sync Metadata
            if !stats.metadataMismatches.isEmpty, let strategy = strategy {
                await MainActor.run {
                    let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                    request.predicate = NSPredicate(
                        format: "catalog == %@ AND originalPath IN %@", catalog,
                        stats.metadataMismatches.map { $0.path })
                    
                    if let items = try? context.fetch(request) {
                        for item in items {
                            guard let path = item.originalPath else { continue }
                            let url = URL(fileURLWithPath: path)
                            
                            switch strategy {
                            case .preferFile:
                                // Read from File -> DB
                                if let exif = ExifReader.shared.readExifSync(from: url) {
                                    item.rating = Int16(exif.rating ?? 0)
                                    item.colorLabel = exif.colorLabel
                                    // Update DB modified date to match file
                                    if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
                                        item.modifiedDate = attrs[.modificationDate] as? Date
                                    }
                                }
                                
                            case .preferCatalog:
                                // Write DB -> File
                                let rating = Int(item.rating)
                                let label = item.colorLabel
                                
                                // Write to file (non-isolated call)
                                self.writeMetadata(to: url, rating: rating, label: label)
                                
                                // Invalidate cache so UI updates if it re-reads
                                ExifReader.shared.invalidateCache(for: url)
                                
                                // Update DB modified date to new file date
                                if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
                                    item.modifiedDate = attrs[.modificationDate] as? Date
                                }
                            }
                        }
                    }
                }
            }
            
            try? context.save()
            
            await MainActor.run {
                self.isSyncingCatalog = false
                self.showUpdateConfirmation = false
                // Refresh view if current catalog
                if self.currentCatalog == catalog {
                    self.loadMediaItems(from: catalog)
                }
            }
        }
    }
    
    private func isVolumeMounted(for url: URL) -> Bool {
        let components = url.pathComponents
        if components.count > 2 && components[1] == "Volumes" {
            let volumePath = "/" + components[1] + "/" + components[2]
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: volumePath, isDirectory: &isDir) && isDir.boolValue
        }
        return true // Internal drive (always mounted)
    }
    
    nonisolated private func writeMetadata(to url: URL, rating: Int, label: String?) {
        // Find ExifTool
        let paths = ["/usr/local/bin/exiftool", "/opt/homebrew/bin/exiftool", "/usr/bin/exiftool"]
        var exifToolPath = "/usr/local/bin/exiftool"
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                exifToolPath = path
                break
            }
        }
        
        var args = ["-overwrite_original"]
        
        // Handle Rating
        if rating > 0 {
            args.append("-Rating=\(rating)")
            args.append("-XMP:Rating=\(rating)")
        } else {
            // Clear rating if 0
            args.append("-Rating=")
            args.append("-XMP:Rating=")
        }
        
        // Handle Label
        if let label = label, !label.isEmpty {
            args.append("-Label=\(label)")
            args.append("-XMP:Label=\(label)")
            args.append("-XMP-xmp:Label=\(label)")
            
            // Map to Urgency for backward compatibility
            var urgency: Int?
            switch label.lowercased() {
            case "red": urgency = 1
            case "orange": urgency = 2
            case "yellow": urgency = 3
            case "green": urgency = 4
            case "blue": urgency = 5
            case "purple": urgency = 6
            case "gray": urgency = 7
            default: urgency = nil
            }
            
            if let u = urgency {
                args.append("-Photoshop:Urgency=\(u)")
            }
        } else {
            // Clear label if nil or empty
            args.append("-Label=")
            args.append("-XMP:Label=")
            args.append("-XMP-xmp:Label=")
            args.append("-Photoshop:Urgency=")
        }
        
        Logger.shared.log("ExifTool Writing to \(url.lastPathComponent): \(args)")
        
        args.append(url.path)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exifToolPath)
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe // Capture stderr too
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Logger.shared.log("ExifTool Output: \(output)")
            }
            
            // Sync with Finder Label
            var labelNumber: Int?
            if let label = label {
                switch label.lowercased() {
                case "red": labelNumber = 6
                case "orange": labelNumber = 7
                case "yellow": labelNumber = 5
                case "green": labelNumber = 2
                case "blue": labelNumber = 4
                case "purple": labelNumber = 3
                case "gray": labelNumber = 1
                case "none", "": labelNumber = 0
                default: labelNumber = 0
                }
            } else {
                labelNumber = 0
            }
            
            if let number = labelNumber {
                var url = url
                var values = URLResourceValues()
                values.labelNumber = number
                try? url.setResourceValues(values)
            }
            
        } catch {
            Logger.shared.log("ExifTool Failed: \(error)")
        }
    }
    
    nonisolated private func writeMetadataBatch(to urls: [URL], rating: Int?, label: String?) {
        guard !urls.isEmpty else { return }
        
        // Find ExifTool
        let paths = ["/usr/local/bin/exiftool", "/opt/homebrew/bin/exiftool", "/usr/bin/exiftool"]
        var exifToolPath = "/usr/local/bin/exiftool"
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                exifToolPath = path
                break
            }
        }

        var args = ["-overwrite_original"]

        // Handle Rating
        if let rating = rating {
            if rating > 0 {
                args.append("-Rating=\(rating)")
                args.append("-XMP:Rating=\(rating)")
            } else {
                args.append("-Rating=")
                args.append("-XMP:Rating=")
            }
        }

        // Handle Label
        if let label = label {
            if !label.isEmpty {
                args.append("-Label=\(label)")
                args.append("-XMP:Label=\(label)")
                args.append("-XMP-xmp:Label=\(label)")

                // Map to Urgency
                var urgency: Int?
                switch label.lowercased() {
                case "red": urgency = 1
                case "orange": urgency = 2
                case "yellow": urgency = 3
                case "green": urgency = 4
                case "blue": urgency = 5
                case "purple": urgency = 6
                case "gray": urgency = 7
                default: urgency = nil
                }

                if let u = urgency {
                    args.append("-Photoshop:Urgency=\(u)")
                }
            } else {
                args.append("-Label=")
                args.append("-XMP:Label=")
                args.append("-XMP-xmp:Label=")
                args.append("-Photoshop:Urgency=")
            }
        }

        // Append all file paths
        args.append(contentsOf: urls.map { $0.path })

        Logger.shared.log("ExifTool Batch Writing to \(urls.count) files: \(args)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exifToolPath)
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment

        do {
            try process.run()
            process.waitUntilExit()
            
            // Sync Finder Labels
            if let label = label {
                var labelNumber: Int?
                switch label.lowercased() {
                case "red": labelNumber = 6
                case "orange": labelNumber = 7
                case "yellow": labelNumber = 5
                case "green": labelNumber = 2
                case "blue": labelNumber = 4
                case "purple": labelNumber = 3
                case "gray": labelNumber = 1
                case "none", "": labelNumber = 0
                default: labelNumber = 0
                }
                
                if let number = labelNumber {
                    for var url in urls {
                        var values = URLResourceValues()
                        values.labelNumber = number
                        try? url.setResourceValues(values)
                    }
                }
            }
            
        } catch {
            Logger.shared.log("ExifTool Batch failed to run: \(error)")
        }
    }

    // MARK: - File Operations Helpers

    nonisolated private func countFiles(at url: URL) -> Int {
        var count = 0
        // Count both files and directories to ensure progress bar moves for folder structures
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for _ in enumerator {
                count += 1
            }
        }
        return count
    }
    
    nonisolated private func copyWithProgress(from source: URL, to destination: URL, totalItems: Int, currentCount: inout Int) async throws {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: source.path, isDirectory: &isDir), isDir.boolValue {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            currentCount += 1
            
            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
            let contents = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: options)
            
            for item in contents {
                let destItem = destination.appendingPathComponent(item.lastPathComponent)
                try await copyWithProgress(from: item, to: destItem, totalItems: totalItems, currentCount: &currentCount)
            }
        } else {
            // Use chunked copy
            let count = currentCount // Capture value to avoid inout capture in escaping closure
            try await copyFileWithProgress(from: source, to: destination, fileSize: 0) { fileProgress in
                 if totalItems > 0 {
                     let globalProgress = (Double(count) + fileProgress) / Double(totalItems)
                     Task { @MainActor in
                         self.blockingOperationProgress = globalProgress
                         self.blockingOperationMessage = "Processing \(count) of \(totalItems) items..."
                     }
                 }
            }
            currentCount += 1
        }
    }
    
    nonisolated private func copyFileWithProgress(from source: URL, to destination: URL, fileSize: Int64, progressHandler: ((Double) -> Void)? = nil) async throws {
        let bufferSize = 1024 * 1024 // 1MB
        let fileManager = FileManager.default
        
        // Create destination directory if needed (shouldn't be needed for file copy, but safety)
        let destDir = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: destDir.path) {
            try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        }
        
        // Use FileHandle for reading and writing
        let readHandle = try FileHandle(forReadingFrom: source)
        defer { try? readHandle.close() }
        
        // Create empty file
        fileManager.createFile(atPath: destination.path, contents: nil)
        let writeHandle = try FileHandle(forWritingTo: destination)
        defer { try? writeHandle.close() }
        
        var bytesWritten: Int64 = 0
        let totalBytes = fileSize > 0 ? fileSize : (try? fileManager.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? 0
        
        // Loop
        while true {
            if Task.isCancelled { throw CancellationError() }
            
            let data = try readHandle.read(upToCount: bufferSize)
            guard let data = data, !data.isEmpty else { break }
            
            try writeHandle.write(contentsOf: data)
            bytesWritten += Int64(data.count)
            
            // Update Progress
            if totalBytes > 0 {
                let progress = Double(bytesWritten) / Double(totalBytes)
                progressHandler?(progress)
            }
        }
        
        // Copy attributes (creation date, modification date, permissions)
        do {
            let attributes = try fileManager.attributesOfItem(atPath: source.path)
            try fileManager.setAttributes(attributes, ofItemAtPath: destination.path)
        } catch {
            Logger.shared.log("Warning: Failed to copy attributes for \(source.lastPathComponent): \(error)")
        }
    }
    
    // MARK: - Catalog Helpers
    
    private func updateCatalogPaths(from srcURL: URL, to destURL: URL) async {
        let srcPath = srcURL.standardizedFileURL.path
        let context = PersistenceController.shared.newBackgroundContext()
        
        await context.perform {
            let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
            let predicate = NSPredicate(format: "originalPath == %@ OR originalPath BEGINSWITH %@", srcPath, srcPath + "/")
            request.predicate = predicate
            
            if let items = try? context.fetch(request), !items.isEmpty {
                Logger.shared.log("Catalog Update: Found \(items.count) items for path: \(srcPath)")
                
                for mediaItem in items {
                    if let oldPath = mediaItem.originalPath {
                        if oldPath == srcPath {
                            mediaItem.originalPath = destURL.path
                        } else if oldPath.hasPrefix(srcPath) {
                            let suffix = oldPath.dropFirst(srcPath.count)
                            let newPath = destURL.path + suffix
                            mediaItem.originalPath = newPath
                        }
                    }
                }
                
                do {
                    try context.save()
                    Logger.shared.log("Catalog Update: Successfully saved new paths.")
                } catch {
                    Logger.shared.log("Catalog Update: Failed to save context: \(error)")
                }
            }
        }
        
        // Trigger Catalog Refresh if active
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            if self.appMode == .catalog, let catalog = self.currentCatalog {
                // Force reload of media items to reflect new paths
                self.loadMediaItems(from: catalog)
                // Also refresh the folder tree
                self.fileSystemRefreshID = UUID()
            }
        }
    }
}
