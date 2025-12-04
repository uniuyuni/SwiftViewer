import Foundation
import SwiftUI

class ThumbnailCacheService {
    static let shared = ThumbnailCacheService()
    
    private var cacheDirectory: URL
    private let memoryCache = NSCache<NSString, NSImage>()
    
    private init() {
        // Default location (will be updated by CatalogService)
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("SwiftViewer")
        cacheDirectory = appSupport.appendingPathComponent("Thumbnails")
        
        // NOTE: Do NOT create directory here to avoid creating empty folders in Application Support
        // unless actually used (e.g. default catalog).
        // try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Configure memory cache
        memoryCache.countLimit = 500 // Keep 500 thumbnails in memory
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }
    
    public func updateCacheDirectory(to url: URL) {
        cacheDirectory = url
        memoryCache.removeAllObjects()
        // Create directory only when explicitly updated (i.e. opening a catalog)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    public enum ThumbnailType {
        case thumbnail
        case preview
    }
    
    func cachePath(for id: UUID, type: ThumbnailType = .thumbnail) -> URL {
        let suffix = type == .preview ? "_preview" : ""
        return cacheDirectory.appendingPathComponent(id.uuidString + suffix + ".jpg")
    }
    
    func saveThumbnail(image: NSImage, for id: UUID, type: ThumbnailType = .thumbnail) {
        // Ensure directory exists before saving
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        // Save to Memory (only thumbnails, previews are too big)
        if type == .thumbnail {
            memoryCache.setObject(image, forKey: id.uuidString as NSString)
        }
        
        // Save to Disk
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.35]) else { return }
        
        let url = cachePath(for: id, type: type)
        do {
            try data.write(to: url)
        } catch {
            print("Failed to save thumbnail: \(error)")
        }
    }
    
    func loadFromMemory(for id: UUID) -> NSImage? {
        return memoryCache.object(forKey: id.uuidString as NSString)
    }
    
    func loadThumbnail(for id: UUID, type: ThumbnailType = .thumbnail) -> NSImage? {
        // 1. Try Memory (only for thumbnails)
        if type == .thumbnail, let cached = memoryCache.object(forKey: id.uuidString as NSString) {
            return cached
        }
        
        // 2. Try Disk
        let url = cachePath(for: id, type: type)
        if let image = NSImage(contentsOf: url) {
            // Populate Memory (only thumbnails)
            if type == .thumbnail {
                memoryCache.setObject(image, forKey: id.uuidString as NSString)
            }
            return image
        }
        return nil
    }
    
    func hasThumbnail(for id: UUID, type: ThumbnailType = .thumbnail) -> Bool {
        if type == .thumbnail && memoryCache.object(forKey: id.uuidString as NSString) != nil { return true }
        return FileManager.default.fileExists(atPath: cachePath(for: id, type: type).path)
    }
    
    func clearCache() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func deleteThumbnail(for id: UUID) {
        memoryCache.removeObject(forKey: id.uuidString as NSString)
        let thumbUrl = cachePath(for: id, type: .thumbnail)
        let previewUrl = cachePath(for: id, type: .preview)
        
        do {
            if FileManager.default.fileExists(atPath: thumbUrl.path) {
                try FileManager.default.removeItem(at: thumbUrl)
                print("Deleted thumbnail: \(thumbUrl.lastPathComponent)")
            } else {
                // print("Thumbnail not found for deletion: \(thumbUrl.lastPathComponent)")
            }
            
            if FileManager.default.fileExists(atPath: previewUrl.path) {
                try FileManager.default.removeItem(at: previewUrl)
            }
        } catch {
            print("Failed to delete thumbnail for \(id): \(error)")
        }
    }
    
    func cleanupOrphanedThumbnails(validUUIDs: Set<UUID>) {
        guard let enumerator = FileManager.default.enumerator(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
        
        var deletedCount = 0
        let validStrings = Set(validUUIDs.map { $0.uuidString })
        
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jpg" else { continue }
            
            let filename = fileURL.deletingPathExtension().lastPathComponent
            // Filename format: UUID.jpg or UUID_preview.jpg
            let uuidString = filename.replacingOccurrences(of: "_preview", with: "")
            
            if !validStrings.contains(uuidString) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    deletedCount += 1
                    // Also remove from memory cache if present
                    memoryCache.removeObject(forKey: uuidString as NSString)
                } catch {
                    print("Failed to delete orphaned thumbnail: \(fileURL.lastPathComponent)")
                }
            }
        }
        
        print("Cleanup: Removed \(deletedCount) orphaned thumbnail files.")
    }
}
