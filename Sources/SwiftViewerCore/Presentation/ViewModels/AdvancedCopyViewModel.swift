import SwiftUI
import Combine
import AppKit
import CoreData

@MainActor
class AdvancedCopyViewModel: NSObject, ObservableObject {
    @Published var sourceRootFolders: [FileItem] = []
    @Published var destinationRootFolders: [FileItem] = []
    
    @Published var selectedSourceFolder: URL? {
        didSet {
            // Immediate feedback
            if let url = selectedSourceFolder {
                // Only load if changed
                if oldValue != url {
                    loadFiles(from: url)
                    UserDefaults.standard.set(url.path, forKey: "advancedCopySource")
                }
            } else {
                isLoading = false
            }
        }
    }
    @Published var expandedSourceFolders: Set<URL> = []
    @Published var includeSubfolders: Bool = true {
        didSet {
            if let url = selectedSourceFolder {
                loadFiles(from: url)
            }
        }
    }
    
    // Files
    @Published var files: [FileItem] = []
    @Published var selectedFileIDs: Set<URL> = [] {
        didSet {
            // Debounce or throttle might be good, but for now direct update
            // Use Task to avoid blocking UI during selection
            Task { @MainActor in
                updatePreview()
            }
        }
    }
    @Published var isLoading: Bool = false
    
    // Destination
    @Published var selectedDestinationFolder: URL? {
        didSet {
            if let url = selectedDestinationFolder {
                UserDefaults.standard.set(url.path, forKey: "advancedCopyDest")
            }
            updatePreview()
        }
    }
    @Published var expandedDestinationFolders: Set<URL> = []
    
    // View Settings
    @Published var thumbnailSize: CGFloat = 100.0
    
    @Published var virtualFolders: [FileItem] = []
    
    // Options
    @Published var addToCatalog: Bool = false
    @Published var selectedCatalog: Catalog? {
        didSet {
            if let url = selectedSourceFolder {
                loadFiles(from: url)
            }
        }
    }
    @Published var grayOutExisting: Bool = UserDefaults.standard.bool(forKey: "advancedCopyGrayOut") {
        didSet {
            UserDefaults.standard.set(grayOutExisting, forKey: "advancedCopyGrayOut")
            if let url = selectedSourceFolder {
                loadFiles(from: url)
            }
        }
    }
    
    @Published var organizeByDate: Bool = true
    @Published var splitEvents: Bool = false
    @Published var eventSplitGap: Int = 120 // Minutes
    @Published var dateFormat: String = "yyyy-MM-dd"
    
    // Copy Progress
    @Published var isCopying: Bool = false {
        didSet {
            // Update close button state
            DispatchQueue.main.async { [weak self] in
                self?.updateCloseButtonState()
            }
        }
    }
    @Published var copyProgress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var processingStage: String = "Processing..."
    
    // Window Management
    private weak var window: NSWindow?
    
    public func setWindow(_ window: NSWindow) {
        self.window = window
        configureWindow()
    }
    
    public func closeWindow() {
        window?.close()
    }
    
    private func configureWindow() {
        guard window != nil else { return }
        
        // Ensure standard close button is enabled initially
        // window.styleMask.remove(.closable) // Removed in Round 43
        
        // No delegate needed
        updateCloseButtonState()
    }
    
    private func updateCloseButtonState() {
        guard let window = window else { return }
        window.standardWindowButton(.closeButton)?.isEnabled = !isCopying
    }
    
    // Catalogs (Round 34 Fix: Fetch manually to avoid View crash)
    @Published var catalogs: [Catalog] = []
    
    override init() {
        super.init()
        refresh()
    }
    
    func refresh() {
        fetchCatalogs()
        Task {
            await loadRootFolders()
        }
    }
    
    func fetchCatalogs() {
        let context = PersistenceController.shared.container.viewContext
        context.perform {
            let request: NSFetchRequest<Catalog> = Catalog.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Catalog.name, ascending: true)]
            
            do {
                let results = try context.fetch(request)
                DispatchQueue.main.async {
                    self.catalogs = results
                    if self.selectedCatalog == nil, let first = results.first {
                        self.selectedCatalog = first
                    }
                }
            } catch {
                Logger.shared.log("Error fetching catalogs: \(error.localizedDescription)")
            }
        }
    }
    
    private func saveExpandedFolders(_ folders: Set<URL>, key: String) {
        let paths = folders.map { $0.path }
        UserDefaults.standard.set(paths, forKey: key)
    }
    
    private func loadExpandedFolders() {
        if let sourcePaths = UserDefaults.standard.stringArray(forKey: "expandedSourceFolders") {
            expandedSourceFolders = Set(sourcePaths.map { URL(fileURLWithPath: $0) })
        }
        if let destPaths = UserDefaults.standard.stringArray(forKey: "expandedDestinationFolders") {
            expandedDestinationFolders = Set(destPaths.map { URL(fileURLWithPath: $0) })
        }
    }

    // Caching
    private var lastProcessedFileIDs: Set<URL> = []
    private var lastProcessedDestination: URL?
    private var lastProcessedOptions: String = "" // Composite key of options that affect structure
    
    private var loadingTask: Task<Void, Never>?
    
    private var previewTask: Task<Void, Never>?
    
    func updatePreview(force: Bool = false) {
        guard let destination = selectedDestinationFolder else {
            virtualFolders = []
            return
        }
        
        Logger.shared.log("AdvancedCopyViewModel: updatePreview called. Selected: \(selectedFileIDs.count), Dest: \(destination.path)")
        
        // Construct a unique key for the current options that affect folder structure
        let currentOptions = "\(organizeByDate)-\(splitEvents)-\(eventSplitGap)"
        
        // Check cache
        if !force && selectedFileIDs == lastProcessedFileIDs && destination == lastProcessedDestination && currentOptions == lastProcessedOptions {
            Logger.shared.log("AdvancedCopyViewModel: Using cached preview.")
            return // Skip if nothing relevant changed
        }
        
        // Only proceed if organizeByDate is true and there are files selected
        guard organizeByDate, !selectedFileIDs.isEmpty else {
            virtualFolders = []
            // Update cache even if empty, to reflect the current state
            self.lastProcessedFileIDs = self.selectedFileIDs
            self.lastProcessedDestination = destination
            self.lastProcessedOptions = currentOptions
            return
        }
        
        isLoading = true
        processingStage = "Generating Preview..."
        previewTask?.cancel()
        
        // Capture values to avoid data race
        let currentFiles = files
        let currentSelection = selectedFileIDs
        let currentDateFormat = dateFormat
        let currentSplitEvents = splitEvents
        let currentGap = eventSplitGap
        
        previewTask = Task.detached(priority: .userInitiated) {
            if Task.isCancelled { return }
            
            let filesToCopy = currentFiles.filter { currentSelection.contains($0.id) }
            Logger.shared.log("AdvancedCopyViewModel: Generating preview for \(filesToCopy.count) files.")
            
            if filesToCopy.isEmpty {
                 await MainActor.run { 
                     self.virtualFolders = []
                     self.isLoading = false
                 }
                 return
            }
            
            var createdFolders: [FileItem] = []
            var folderNames: Set<String> = []
            let formatter = DateFormatter()
            formatter.dateFormat = currentDateFormat
            
            // Helper for detached task
            func getDetachedDate(for url: URL) async -> Date? {
                // Use ExifReader to match the actual copy logic
                if let metadata = await ExifReader.shared.readExif(from: url) {
                    return metadata.dateTimeOriginal
                }
                // Fallback to creation date if no Exif
                return try? FileManager.default.attributesOfItem(atPath: url.path)[.creationDate] as? Date
            }

            // 1. Identify files needing Exif (All images)
            let imageFiles = filesToCopy.filter {
                let ext = $0.url.pathExtension.lowercased()
                return FileConstants.allowedImageExtensions.contains(ext)
            }
            
            // Optimization: If too many files, skip Exif for preview and use FileSystem date
            // This prevents hanging on large folders.
            let useFastPreview = filesToCopy.count > 1000
            if useFastPreview {
                Logger.shared.log("AdvancedCopyViewModel: Large dataset (\(filesToCopy.count) items). Using FileSystem dates for preview.")
            }
            
            // 2. Batch read Exif for ALL images (Only if not fast preview)
            var exifData: [URL: ExifMetadata] = [:]
            if !useFastPreview {
                let imageURLs = imageFiles.map { $0.url }
                if !imageURLs.isEmpty {
                    await MainActor.run { self.processingStage = "Reading Metadata (\(imageURLs.count))..." }
                    Logger.shared.log("AdvancedCopyViewModel: Batch reading Exif for \(imageURLs.count) files.")
                    exifData = await ExifReader.shared.readExifBatch(from: imageURLs)
                }
            }
            
            var filesWithDates: [(FileItem, Date)] = []
            
            // 3. Process all files to get dates
            for file in filesToCopy {
                if Task.isCancelled { return }
                
                var date: Date?
                
                // Check if we have batch loaded Exif
                if let meta = exifData[file.url], let dt = meta.dateTimeOriginal {
                    date = dt
                } else {
                    // Fallback to FileItem creationDate (Fastest)
                    if let creation = file.creationDate {
                         date = creation
                    } else {
                         // Last resort: Disk read (Slow)
                         date = await getDetachedDate(for: file.url)
                    }
                }
                
                filesWithDates.append((file, date ?? Date.distantPast))
            }
            
            if currentSplitEvents {
                let sortedFiles = filesWithDates.sorted { $0.1 < $1.1 }
                
                var eventStartDate: Date?
                var lastDate: Date?
                
                for (_, date) in sortedFiles {
                    if Task.isCancelled { return }
                    if date == Date.distantPast { continue }
                    
                    if let last = lastDate {
                        let gap = date.timeIntervalSince(last)
                        if gap > Double(currentGap * 60) { // Gap is in minutes
                            if let start = eventStartDate {
                                formatter.dateFormat = "yyyy-MM-dd_HHmm"
                                let name = formatter.string(from: start)
                                folderNames.insert(name)
                            }
                            eventStartDate = date
                        }
                    } else {
                        eventStartDate = date
                    }
                    lastDate = date
                }
                
                if let start = eventStartDate {
                    formatter.dateFormat = "yyyy-MM-dd_HHmm"
                    let name = formatter.string(from: start)
                    folderNames.insert(name)
                }
                
            } else {
                // Simple date grouping
                for (_, date) in filesWithDates {
                    if Task.isCancelled { return }
                    if date != Date.distantPast {
                         folderNames.insert(formatter.string(from: date))
                    }
                }
            }
            
            // Ensure isLoading is reset
            defer {
                Task { @MainActor in
                    // Only reset if we are still the active task? 
                    // No, simpler: just reset. If a new task started, it set isLoading=true.
                    // But if we set it to false, we might hide the new task's loading.
                    // However, we check Task.isCancelled.
                    if !Task.isCancelled {
                         self.isLoading = false
                    }
                }
            }

            if Task.isCancelled { return }
            
            Logger.shared.log("AdvancedCopyViewModel: Generated folder names: \(folderNames)")
            
            // Create FileItems for the folders
            // Include folders that DO NOT EXIST on disk as virtual.
            // Existing folders will be shown by SimpleFolderTreeView reading from disk.
            // BUT we want to mark them as CONFLICT if they exist.
            // SimpleFolderTreeView merges virtual and real. If virtual has isConflict=true, it overrides.
            
            createdFolders = folderNames.compactMap { name in
                let url = destination.appendingPathComponent(name).standardizedFileURL
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                    // Exists! Mark as conflict.
                    var item = FileItem(url: url, isDirectory: true, isAvailable: true)
                    item.isConflict = true
                    return item
                } else {
                    return FileItem(url: url, isDirectory: true, isAvailable: false)
                }
            }
            
            let result = createdFolders.sorted { $0.name < $1.name }
            
            await MainActor.run {
                // Check if still relevant (though cancellation handles most cases)
                guard !Task.isCancelled else { return }
                guard self.selectedDestinationFolder == destination else { return }
                
                // Update virtual folders
                self.virtualFolders = result
                
                self.lastProcessedFileIDs = currentSelection
                self.lastProcessedDestination = destination
                self.lastProcessedOptions = currentOptions
                let conflictCount = result.filter { $0.isConflict }.count
                Logger.shared.log("AdvancedCopyViewModel: Preview updated with \(result.count) virtual folders (\(conflictCount) conflicts).")
            }
        }
    }
    
    private func getDate(for url: URL) async -> Date? {
        if let metadata = await ExifReader.shared.readExif(from: url) {
            return metadata.dateTimeOriginal
        }
        return try? FileManager.default.attributesOfItem(atPath: url.path)[.creationDate] as? Date
    }
    
    private let fileSystemService = FileSystemService.shared
    private let mediaRepository = MediaRepository()
    private let collectionRepository = CollectionRepository()
    
    func loadRootFolders() async {
        // Source: Volumes + Standard Folders
        // Disable file counting for performance (Round 9 fix)
        // FileSystemService methods are now nonisolated (synchronous)
        
        // Move to background to avoid blocking main thread
        let (sourceRoots, destRoots) = await Task.detached(priority: .userInitiated) {
            // getRootFolders now includes volumes, so we don't need to call getMountedVolumes separately
            let roots = FileSystemService.shared.getRootFolders(calculateCounts: false)
            return (roots, roots)
        }.value
        
        self.sourceRootFolders = sourceRoots
        self.destinationRootFolders = destRoots
        
        // Auto-select last mounted volume OR last used folder
        
        // Auto-select last mounted volume OR last used folder
        if let lastSource = UserDefaults.standard.string(forKey: "advancedCopySource") {
             let url = URL(fileURLWithPath: lastSource)
             
             // Validate if the path is on a currently mounted volume
             var isValid = false
             if url.path.hasPrefix("/Volumes/") {
                 // Check if the volume root exists in our detected volumes
                 // This prevents accessing stale/unmounted volumes which can hang or crash
                 let volumeName = url.pathComponents.count > 2 ? url.pathComponents[2] : ""
                 if !volumeName.isEmpty {
                     let volumeRoot = URL(fileURLWithPath: "/Volumes/\(volumeName)")
                     // sourceRoots contains volumes + standard folders.
                     // We can check if the volume root is in sourceRoots
                     if sourceRoots.contains(where: { $0.url.path == volumeRoot.path }) {
                         // Volume is mounted, now check if directory exists
                         var isDir: ObjCBool = false
                         if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue {
                             isValid = true
                         }
                     } else {
                         Logger.shared.log("Last source volume '/Volumes/\(volumeName)' is not mounted. Resetting to default.")
                     }
                 }
             } else {
                 // Standard path (e.g. /Users/...)
                 var isDir: ObjCBool = false
                 if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue {
                     isValid = true
                 }
             }
             
             if isValid {
                 self.selectedSourceFolder = url
             } else if let firstRoot = sourceRoots.first {
                 self.selectedSourceFolder = firstRoot.url
             }
        } else if let firstRoot = sourceRoots.first {
            self.selectedSourceFolder = firstRoot.url
        }
        
        if let lastDest = UserDefaults.standard.string(forKey: "advancedCopyDestination") {
            Logger.shared.log("AdvancedCopyViewModel: Loading last destination: \(lastDest)")
            let url = URL(fileURLWithPath: lastDest)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue {
                self.selectedDestinationFolder = url
            } else {
                self.destinationRootFolders = destRoots
            }
        } else {
            self.destinationRootFolders = destRoots
        }
        
        if let lastSource = UserDefaults.standard.string(forKey: "advancedCopySource") {
             Logger.shared.log("AdvancedCopyViewModel: Loading last source: \(lastSource)")
        }
        
        // Ensure destination path is expanded
        if let dest = self.selectedDestinationFolder {
            self.expandPath(to: dest, in: &self.expandedDestinationFolders)
        }
        if let source = self.selectedSourceFolder {
            self.expandPath(to: source, in: &self.expandedSourceFolders)
        }
    }
    
    private func expandPath(to url: URL, in set: inout Set<URL>) {
        var current = url
        while current.pathComponents.count > 1 {
            current = current.deletingLastPathComponent()
            set.insert(current)
        }
    }
    
    func loadFiles(from url: URL) {
        // Prevent redundant loading if already processing the same folder
        if isLoading && selectedSourceFolder == url {
            Logger.shared.log("AdvancedCopyViewModel: Already loading \(url.path), skipping.")
            return
        }
        
        // Cancel previous task
        loadingTask?.cancel()
        
        // Reset state immediately
        self.isLoading = true
        self.processingStage = "Listing Files..."
        self.files = []
        
        // Capture values to avoid accessing MainActor properties from detached task
        let recursive = self.includeSubfolders
        let grayOut = self.grayOutExisting
        let catalogID = self.selectedCatalog?.objectID
        
        Logger.shared.log("DEBUG: AdvancedCopy loadFiles from \(url.path)")
        loadingTask = Task.detached(priority: .userInitiated) { [weak self] in
            // Background work
            if Task.isCancelled { return }
            
            do {
                // 1. Get Files (Slow I/O)
                // Use the captured 'recursive' value
                // FileSystemService methods are now nonisolated (synchronous)
                // Add timeout using Task.sleep
                let allFiles: [FileItem]
                
                allFiles = try await withThrowingTaskGroup(of: [FileItem].self) { group in
                    group.addTask {
                        // Skip metadata for performance
                        return try FileSystemService.shared.getFiles(in: url, recursive: recursive, fetchMetadata: false)
                    }
                    
                    group.addTask {
                        try await Task.sleep(nanoseconds: 10 * 1_000_000_000) // 10 seconds timeout
                        Logger.shared.log("AdvancedCopyViewModel: loadFiles timed out.")
                        throw CancellationError()
                    }
                    
                    guard let result = try await group.next() else { return [] }
                    group.cancelAll()
                    return result
                }
                
                if Task.isCancelled { return }
                
                // 2. Check duplicates (Core Data)
                // mediaFiles is now allFiles since filtering is done in getFiles
                let mediaFiles = allFiles
                
                let processedFiles: [FileItem]
                
                // 2. Check duplicates (Core Data)
                if grayOut, let catalogID = catalogID {
                    let context = PersistenceController.shared.newBackgroundContext()
                    var existingPaths: Set<String> = []
                    
                    context.performAndWait {
                        let request: NSFetchRequest<NSFetchRequestResult> = MediaItem.fetchRequest()
                        request.predicate = NSPredicate(format: "catalog == %@", catalogID)
                        request.resultType = .dictionaryResultType
                        request.propertiesToFetch = ["originalPath"]
                        
                        if let results = try? context.fetch(request) as? [[String: String]] {
                            existingPaths = Set(results.compactMap { $0["originalPath"] })
                        }
                    }
                    
                    processedFiles = mediaFiles.map { file in
                        let exists = existingPaths.contains(file.url.path)
                        return FileItem(url: file.url, isDirectory: false, isAvailable: !exists, uuid: file.uuid)
                    }
                } else {
                    processedFiles = mediaFiles
                }
                
                if Task.isCancelled { return }
                
                // 3. Sort
                let sortedFiles = FileSortService.sortFiles(processedFiles, by: .name, ascending: true)
                
                // 4. Update UI
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    // Double check if we are still looking at the same folder
                    guard self.selectedSourceFolder == url else { return }
                    
                    self.files = sortedFiles
                    // Auto-select all files by default
                    self.selectedFileIDs = Set(sortedFiles.map { $0.id })
                    self.isLoading = false
                    
                    // Force preview update AFTER state is settled
                    // We dispatch this asynchronously to allow the current layout pass (grid update) to complete first
                    Task { @MainActor in
                        self.updatePreview(force: true)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    Logger.shared.log("Error loading files: \(error)")
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        self.isLoading = false
                    }
                }
            }
        }
    }
    
    func performCopy() {
        guard let destURL = selectedDestinationFolder else {
            statusMessage = "Please select a destination folder."
            return
        }
        
        let filesToCopy = files.filter { selectedFileIDs.contains($0.id) }
        
        if filesToCopy.isEmpty {
            statusMessage = "No files selected."
            return
        }
        
        isCopying = true
        copyProgress = 0.0
        statusMessage = "Copying \(filesToCopy.count) items..."
        
        Task {
            let total = Double(filesToCopy.count)
            var current = 0.0
            var copiedURLs: [URL] = []
            var lastUpdate = Date()
            
            // 1. Batch read Exif for ALL images to speed up date analysis
            let imageFiles = filesToCopy.filter {
                let ext = $0.url.pathExtension.lowercased()
                return FileConstants.allowedImageExtensions.contains(ext)
            }
            
            var exifData: [URL: ExifMetadata] = [:]
            if !imageFiles.isEmpty {
                await MainActor.run { self.statusMessage = "Reading Metadata (\(imageFiles.count))..." }
                let imageURLs = imageFiles.map { $0.url }
                exifData = await ExifReader.shared.readExifBatch(from: imageURLs)
            }
            
            // Helper to get date (using batch cache)
            func getDate(for file: FileItem) async -> Date? {
                if let meta = exifData[file.url], let dt = meta.dateTimeOriginal {
                    return dt
                }
                // Fallback to FileItem creationDate (Fastest)
                if let creation = file.creationDate {
                     return creation
                }
                // Last resort: Disk read
                return try? FileManager.default.attributesOfItem(atPath: file.url.path)[.creationDate] as? Date
            }
            
            // If splitting events OR organizing by date, we need dates
            var filesWithDates: [(FileItem, Date)] = []
            if organizeByDate {
                await MainActor.run { self.statusMessage = "Analyzing dates..." }
                for file in filesToCopy {
                    if let date = await getDate(for: file) {
                        filesWithDates.append((file, date))
                    } else {
                        filesWithDates.append((file, Date.distantPast))
                    }
                }
            }
            
            // Group files into events
            var events: [(folderName: String, files: [FileItem])] = []
            
            if organizeByDate {
                if splitEvents {
                    // Sort by date
                    filesWithDates.sort { $0.1 < $1.1 }
                    
                    var currentEventFiles: [FileItem] = []
                    var eventStartDate: Date? = nil
                    var lastDate: Date? = nil
                    
                    for (file, date) in filesWithDates {
                        if let last = lastDate {
                            let diff = date.timeIntervalSince(last)
                            if diff > Double(eventSplitGap * 60) { // Gap > eventSplitGap minutes -> New Event
                                // Close current event
                                if let start = eventStartDate {
                                    let formatter = DateFormatter()
                                    formatter.dateFormat = "yyyy-MM-dd_HHmm"
                                    let folderName = formatter.string(from: start)
                                    events.append((folderName, currentEventFiles))
                                }
                                currentEventFiles = []
                                eventStartDate = date
                            }
                        } else {
                            eventStartDate = date
                        }
                        
                        currentEventFiles.append(file)
                        lastDate = date
                    }
                    
                    // Close last event
                    if let start = eventStartDate, !currentEventFiles.isEmpty {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd_HHmm"
                        let folderName = formatter.string(from: start)
                        events.append((folderName, currentEventFiles))
                    }
                    
                } else {
                    // Just group by YYYY-MM-DD
                    var dateGroups: [String: [FileItem]] = [:]
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    
                    for (file, date) in filesWithDates {
                        let key = formatter.string(from: date)
                        dateGroups[key, default: []].append(file)
                    }
                    
                    // Sort keys to ensure deterministic order
                    let sortedKeys = dateGroups.keys.sorted()
                    for key in sortedKeys {
                        if let files = dateGroups[key] {
                            events.append((key, files))
                        }
                    }
                }
            } else {
                // No grouping
                events.append(("", filesToCopy))
            }
            
            // Process Events
            for event in events {
                let folderName = event.folderName
                let targetFolder = folderName.isEmpty ? destURL : destURL.appendingPathComponent(folderName)
                
                if !folderName.isEmpty {
                    try? FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)
                }
                
                for file in event.files {
                    let destFile = targetFolder.appendingPathComponent(file.url.lastPathComponent)
                    
                    do {
                        if FileManager.default.fileExists(atPath: destFile.path) {
                            print("File exists, skipping: \(destFile.path)")
                        } else {
                            try FileManager.default.copyItem(at: file.url, to: destFile)
                            copiedURLs.append(destFile)
                        }
                    } catch {
                        print("Copy failed for \(file.url): \(error)")
                    }
                    
                    current += 1
                    
                    // Throttle updates to avoid flooding Main Thread (max 10 updates/sec)
                    let now = Date()
                    if now.timeIntervalSince(lastUpdate) > 0.1 || current == total {
                        let progress = current / total
                        await MainActor.run {
                            self.copyProgress = progress
                        }
                        lastUpdate = now
                    }
                }
            }
            
            // Add to Catalog if requested
            if addToCatalog, let catalog = selectedCatalog, !copiedURLs.isEmpty {
                await MainActor.run {
                    self.statusMessage = "Adding to Catalog..."
                }
                let catalogID = catalog.objectID
                try? await mediaRepository.importMediaItems(from: copiedURLs, to: catalogID)
            }
            
            await MainActor.run {
                self.isCopying = false
                self.copyProgress = 1.0
                self.statusMessage = "Copy complete. \(copiedURLs.count) files copied."
                Logger.shared.log("AdvancedCopyViewModel: Copy complete.")
                
                // Refresh destination tree to show new folders
                if let dest = self.selectedDestinationFolder {
                    self.refreshDestinationTree(at: dest)
                    // Also trigger preview update to clear virtual folders that are now real
                    self.updatePreview()
                }
                
                // Notify main app to refresh
                NotificationCenter.default.post(name: .refreshAll, object: nil)
            }
        }
    }
    
    private func refreshDestinationTree(at url: URL) {
        // Notify SimpleFolderTreeView to refresh
        // We can use a global notification or a specific one.
        // Let's use the existing fileSystemRefreshID in MainViewModel if possible, 
        // but AdvancedCopyViewModel is separate.
        // We'll post a notification that SimpleFolderTreeView listens to.
        NotificationCenter.default.post(name: .refreshFileSystem, object: nil)
        
        // Also, we should probably clear the "virtualFolders" if they now exist, 
        // so they don't show as conflicts immediately? 
        // Or maybe the user WANTS to see them as conflicts if they try to copy again?
        // User said: "After copy... confirm creation... it remains grayed out".
        // This implies they want to see it as a normal folder.
        // If I return `nil` in updatePreview when it exists, it shows as Normal (Real).
        // If I return `isConflict`, it shows as Red.
        // I should probably switch back to `return nil` (Skip) if it exists, 
        // BUT the user asked for "Red if exists" in the previous request.
        // "In copy mode, if the virtual folder... already exists... display in red."
        // So Red is correct.
        // The "Gray" means it didn't detect existence.
    }
}

extension Notification.Name {
    static let refreshFileSystem = Notification.Name("refreshFileSystem")
}
