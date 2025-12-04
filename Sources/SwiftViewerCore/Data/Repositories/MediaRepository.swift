import Foundation
import CoreData
import AppKit
import ImageIO

public protocol MediaRepositoryProtocol {
    func addMediaItem(from url: URL, to catalog: Catalog) async throws -> MediaItem
    func fetchMediaItems(in catalog: Catalog) throws -> [MediaItem]
    func importMediaItems(from urls: [URL], to catalogID: NSManagedObjectID, progress: (@Sendable (Double) -> Void)?) async throws -> [NSManagedObjectID]
}

public class MediaRepository: MediaRepositoryProtocol {
    private let context: NSManagedObjectContext
    
    public init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }
    
    public func addMediaItem(from url: URL, to catalog: Catalog) async throws -> MediaItem {
        // Use the injected context
        let context = self.context
        
        // We need to await Exif data, so we can't be inside a synchronous perform block if we were using one.
        // But here we are just using the context directly (assuming main thread or we are careful).
        // Since this is async now, we should ensure we are on the correct actor/queue for the context.
        // If context is viewContext, we should be on MainActor.
        
        let catalogID = catalog.objectID
        let metadata = await ExifReader.shared.readExif(from: url)
        
        return try await context.perform {
            // Fetch catalog inside context
            guard let catalog = try? context.existingObject(with: catalogID) as? Catalog else {
                throw NSError(domain: "MediaRepository", code: 404, userInfo: [NSLocalizedDescriptionKey: "Catalog not found"])
            }
            
            let item = MediaItem(context: context)
            item.id = UUID()
            item.originalPath = url.path
            item.fileName = url.lastPathComponent
            item.importDate = Date()
            item.modifiedDate = Date()
            item.catalog = catalog
            item.fileExists = FileManager.default.fileExists(atPath: url.path)
            
            // Basic attributes
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                item.fileSize = (attributes[.size] as? Int64) ?? 0
                item.captureDate = attributes[.creationDate] as? Date
            }
            
            // This is synchronous, assuming FileSystemService is actor but we are calling a nonisolated method or we need to await it?
            // FileSystemService.getColorLabel is nonisolated now.
            item.colorLabel = FileSystemService.shared.getColorLabel(from: url)
            
            // Determine type
            let ext = url.pathExtension.lowercased()
            if FileConstants.allowedVideoExtensions.contains(ext) {
                item.mediaType = "video"
            } else {
                item.mediaType = "image"
                
                // Read EXIF
                if let metadata = metadata {
                    let exif = ExifData(context: context)
                    exif.id = UUID()
                    exif.cameraMake = metadata.cameraMake
                    exif.cameraModel = metadata.cameraModel
                    exif.lensModel = metadata.lensModel
                    exif.focalLength = metadata.focalLength ?? 0
                    exif.aperture = metadata.aperture ?? 0
                    exif.shutterSpeed = metadata.shutterSpeed
                    exif.iso = Int32(metadata.iso ?? 0)
                    exif.dateTimeOriginal = metadata.dateTimeOriginal
                    
                    item.exifData = exif
                    item.width = Int32(metadata.width ?? 0)
                    item.height = Int32(metadata.height ?? 0)
                    item.orientation = Int16(metadata.orientation ?? 1)
                    
                    if let date = metadata.dateTimeOriginal {
                        item.captureDate = date
                    }
                }
            }
            
            try context.save()
            return item
        }
    }
    
    // New method for background import
    public func importMediaItems(from urls: [URL], to catalogID: NSManagedObjectID, progress: (@Sendable (Double) -> Void)? = nil) async throws -> [NSManagedObjectID] {
        let container = PersistenceController.shared.container
        let allowedExtensions = FileConstants.allAllowedExtensions
        
        if Task.isCancelled { throw CancellationError() }
        progress?(0.05)
        
        // 1. Scan files (I/O) - Can be done in parallel
        // We'll do a simple scan first
        let filesToImport = scanFiles(from: urls, allowedExtensions: Set(allowedExtensions))
        
        if Task.isCancelled { throw CancellationError() }
        progress?(0.1)
        
        if filesToImport.isEmpty {
            progress?(1.0)
            return []
        }
        
        // 2. Read Exif Data (Async I/O)
        // We do this BEFORE entering the Core Data context to avoid blocking the DB thread
        // We can split this into chunks for progress
        let totalFiles = Double(filesToImport.count)
        var exifDataMap: [URL: ExifMetadata] = [:]
        
        // Chunk size for progress updates
        let chunkSize = 50
        // let chunks = filesToImport.chunked(into: chunkSize)
        
        var processedCount = 0
        
        for i in stride(from: 0, to: filesToImport.count, by: chunkSize) {
            if Task.isCancelled { throw CancellationError() }
            
            let end = min(i + chunkSize, filesToImport.count)
            let chunk = Array(filesToImport[i..<end])
            
            let chunkMap = await ExifReader.shared.readExifBatch(from: chunk)
            exifDataMap.merge(chunkMap) { (_, new) in new }
            
            processedCount += chunk.count
            let currentProgress = 0.1 + (0.7 * (Double(processedCount) / totalFiles)) // 10% to 80%
            progress?(currentProgress)
        }
        
        if Task.isCancelled { throw CancellationError() }
        
        // 3. Write to DB (Core Data)
        // Use newBackgroundContext and await perform to ensure we wait for completion
        let bgContext = container.newBackgroundContext()
        bgContext.automaticallyMergesChangesFromParent = true
        bgContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        let result: [NSManagedObjectID] = try await bgContext.perform {
            if Task.isCancelled { throw CancellationError() }
            
            guard let catalog = bgContext.object(with: catalogID) as? Catalog else { return [] }
            
            // Fetch existing paths to prevent duplicates
            let existingPathsRequest: NSFetchRequest<NSFetchRequestResult> = MediaItem.fetchRequest()
            existingPathsRequest.predicate = NSPredicate(format: "catalog == %@ AND originalPath IN %@", catalog, filesToImport.map { $0.path })
            existingPathsRequest.resultType = .dictionaryResultType
            existingPathsRequest.propertiesToFetch = ["originalPath"]
            
            let existingResults = try? bgContext.fetch(existingPathsRequest) as? [[String: String]]
            let existingPathSet = Set(existingResults?.compactMap { $0["originalPath"] } ?? [])
            
            var savedCount = 0
            
            var importedItems: [MediaItem] = []
            
            for (_, url) in filesToImport.enumerated() {
                if Task.isCancelled { throw CancellationError() }
                
                if existingPathSet.contains(url.path) {
                    continue // Skip existing
                }
                
                let item = MediaItem(context: bgContext)
                item.id = UUID()
                item.originalPath = url.path
                item.fileName = url.lastPathComponent
                item.catalog = catalog
                item.importDate = Date()
                item.modifiedDate = Date() // Default to now, update from attributes
                item.fileExists = FileManager.default.fileExists(atPath: url.path)
                
                // Basic attributes
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                    item.fileSize = (attributes[.size] as? Int64) ?? 0
                    item.captureDate = (attributes[.creationDate] as? Date) ?? item.captureDate
                    if let modDate = attributes[.modificationDate] as? Date {
                        item.modifiedDate = modDate
                    }
                }
                
                item.colorLabel = FileSystemService.shared.getColorLabel(from: url)
                
                // Determine type
                let ext = url.pathExtension.lowercased()
                if FileConstants.allowedVideoExtensions.contains(ext) {
                    item.mediaType = "video"
                } else {
                    item.mediaType = "image"
                    
                    // Use pre-loaded EXIF
                    if let metadata = exifDataMap[url] {
                        // Map Item Level Metadata
                        item.rating = Int16(metadata.rating ?? 0)
                        item.colorLabel = metadata.colorLabel
                        item.isFavorite = metadata.isFavorite ?? false
                        item.flagStatus = Int16(metadata.flagStatus ?? 0)
                        
                        let exif = ExifData(context: bgContext)
                        exif.id = UUID()
                        exif.cameraMake = metadata.cameraMake
                        exif.cameraModel = metadata.cameraModel
                        exif.lensModel = metadata.lensModel
                        exif.focalLength = metadata.focalLength ?? 0
                        exif.aperture = metadata.aperture ?? 0
                        exif.shutterSpeed = metadata.shutterSpeed
                        exif.iso = Int32(metadata.iso ?? 0)
                        exif.dateTimeOriginal = metadata.dateTimeOriginal
                        
                        // Extended Fields
                        exif.software = metadata.software
                        exif.meteringMode = metadata.meteringMode
                        exif.flash = metadata.flash
                        exif.whiteBalance = metadata.whiteBalance
                        exif.exposureProgram = metadata.exposureProgram
                        exif.exposureCompensation = metadata.exposureCompensation ?? 0.0
                        
                        // New Fields
                        exif.brightnessValue = metadata.brightnessValue ?? 0.0
                        exif.exposureBias = metadata.exposureBias ?? 0.0
                        exif.serialNumber = metadata.serialNumber
                        exif.title = metadata.title
                        exif.caption = metadata.caption
                        exif.latitude = metadata.latitude ?? 0.0
                        exif.longitude = metadata.longitude ?? 0.0
                        exif.altitude = metadata.altitude ?? 0.0
                        exif.imageDirection = metadata.imageDirection ?? 0.0
                        
                        if let raw = metadata.rawProps {
                            exif.rawProps = try? JSONSerialization.data(withJSONObject: raw, options: [])
                        }
                        
                        item.exifData = exif
                        item.width = Int32(metadata.width ?? 0)
                        item.height = Int32(metadata.height ?? 0)
                        item.orientation = Int16(metadata.orientation ?? 1)
                        
                        if let date = metadata.dateTimeOriginal {
                            item.captureDate = date
                        }
                    }
                    
                    // Enqueue for background thumbnail generation
                    importedItems.append(item)
                }
                
                savedCount += 1
                if savedCount % 100 == 0 {
                    if Task.isCancelled { throw CancellationError() }
                    try? bgContext.save()
                }
            }
            
            if Task.isCancelled { throw CancellationError() }
            
            if bgContext.hasChanges {
                try bgContext.save()
                print("DEBUG: Import saved \(savedCount) items to Core Data.")
            } else {
                print("DEBUG: No changes to save in import.")
            }
            
            // Return imported IDs for caller to handle thumbnails
            return importedItems.map { $0.objectID }
        }
        
        progress?(1.0)
        return result
    }
    
    public func fetchMediaItems(in catalog: Catalog) throws -> [MediaItem] {
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "catalog == %@", catalog)
        request.relationshipKeyPathsForPrefetching = ["exifData"] // Prefetch ExifData to avoid N+1 faults
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MediaItem.importDate, ascending: false)]
        return try context.fetch(request)
    }
    
    private func generateThumbnail(for url: URL) -> NSImage? {
        let ext = url.pathExtension.lowercased()
        let isRaw = FileConstants.allowedImageExtensions.contains(ext) && !["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"].contains(ext)
        
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: !isRaw,
            kCGImageSourceThumbnailMaxPixelSize: 300
        ]
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
    }
    
    private func scanFiles(from urls: [URL], allowedExtensions: Set<String>) -> [URL] {
        var filesToImport: [URL] = []
        
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                        for case let fileURL as URL in enumerator {
                            let ext = fileURL.pathExtension.lowercased()
                            if allowedExtensions.contains(ext) {
                                filesToImport.append(fileURL)
                            }
                        }
                    }
                } else {
                    let ext = url.pathExtension.lowercased()
                    if allowedExtensions.contains(ext) {
                        filesToImport.append(url)
                    }
                }
            }
        }
        return filesToImport
    }
    
    // MARK: - Favorite and Flag Status
    
    public func updateFavorite(for items: [MediaItem], isFavorite: Bool) {
        context.perform {
            for item in items {
                item.isFavorite = isFavorite
            }
            try? self.context.save()
        }
    }
    
    public func updateFlagStatus(for items: [MediaItem], status: Int16) {
        context.perform {
            for item in items {
                item.flagStatus = status
                // Also update legacy isFlagged for compatibility
                item.isFlagged = (status != 0)
            }
            try? self.context.save()
        }
    }
}
