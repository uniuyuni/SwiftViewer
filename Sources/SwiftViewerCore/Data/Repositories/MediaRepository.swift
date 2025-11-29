import Foundation
import CoreData
import AppKit
import ImageIO

protocol MediaRepositoryProtocol {
    func addMediaItem(from url: URL, to catalog: Catalog) async throws -> MediaItem
    func fetchMediaItems(in catalog: Catalog) throws -> [MediaItem]
    func importMediaItems(from urls: [URL], to catalogID: NSManagedObjectID) async throws
}

class MediaRepository: MediaRepositoryProtocol {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }
    
    func addMediaItem(from url: URL, to catalog: Catalog) async throws -> MediaItem {
        // Use the injected context
        let context = self.context
        
        // We need to await Exif data, so we can't be inside a synchronous perform block if we were using one.
        // But here we are just using the context directly (assuming main thread or we are careful).
        // Since this is async now, we should ensure we are on the correct actor/queue for the context.
        // If context is viewContext, we should be on MainActor.
        
        let metadata = await ExifReader.shared.readExif(from: url)
        
        return try await context.perform {
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
    func importMediaItems(from urls: [URL], to catalogID: NSManagedObjectID) async throws {
        let container = PersistenceController.shared.container
        let allowedExtensions = FileConstants.allAllowedExtensions
        
        // 1. Scan files (I/O) - Can be done in parallel
        // We'll do a simple scan first
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
        
        // 2. Read Exif Data (Async I/O)
        // We do this BEFORE entering the Core Data context to avoid blocking the DB thread
        let exifDataMap = await ExifReader.shared.readExifBatch(from: filesToImport)
        
        // 3. Write to DB (Core Data)
        try await container.performBackgroundTask { context in
            guard let catalog = context.object(with: catalogID) as? Catalog else { return }
            
            // Fetch existing paths to prevent duplicates
            let existingPathsRequest: NSFetchRequest<NSFetchRequestResult> = MediaItem.fetchRequest()
            existingPathsRequest.predicate = NSPredicate(format: "catalog == %@ AND originalPath IN %@", catalog, filesToImport.map { $0.path })
            existingPathsRequest.resultType = .dictionaryResultType
            existingPathsRequest.propertiesToFetch = ["originalPath"]
            
            let existingResults = try? context.fetch(existingPathsRequest) as? [[String: String]]
            let existingPathSet = Set(existingResults?.compactMap { $0["originalPath"] } ?? [])
            
            for url in filesToImport {
                if existingPathSet.contains(url.path) {
                    continue // Skip existing
                }
                
                let item = MediaItem(context: context)
                item.id = UUID()
                item.originalPath = url.path
                item.fileName = url.lastPathComponent
                item.catalog = catalog
                item.importDate = Date()
                item.modifiedDate = Date()
                item.fileExists = FileManager.default.fileExists(atPath: url.path)
                
                // Basic attributes
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                    item.fileSize = (attributes[.size] as? Int64) ?? 0
                    item.captureDate = (attributes[.creationDate] as? Date) ?? item.captureDate // Use existing if not found
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
                    
                    // Generate and Cache Thumbnail (for offline access)
                    // We skip this for now to speed up import, or do it in a separate pass?
                    // The original code had it.
                    // But generateThumbnail is synchronous.
                    // We can't easily do it here without blocking the context.
                    // Let's rely on on-demand generation for now, or add a "Generate Previews" task later.
                }
            }
            
            try context.save()
        }
    }
    
    func fetchMediaItems(in catalog: Catalog) throws -> [MediaItem] {
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "catalog == %@", catalog)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MediaItem.importDate, ascending: false)]
        return try context.fetch(request)
    }
    
    private func generateThumbnail(for url: URL) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 300
        ]
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
    }
}
