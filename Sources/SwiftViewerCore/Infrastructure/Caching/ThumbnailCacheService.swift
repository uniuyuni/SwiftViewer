import Foundation
import SwiftUI

class ThumbnailCacheService {
    static let shared = ThumbnailCacheService()
    
    private let cacheDirectory: URL
    private let memoryCache = NSCache<NSString, NSImage>()
    
    private init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("SwiftViewer")
        cacheDirectory = appSupport.appendingPathComponent("Thumbnails")
        
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Configure memory cache
        memoryCache.countLimit = 500 // Keep 500 thumbnails in memory
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
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
        // Save to Memory (only thumbnails, previews are too big)
        if type == .thumbnail {
            memoryCache.setObject(image, forKey: id.uuidString as NSString)
        }
        
        // Save to Disk
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.35]) else { return }
        
        let url = cachePath(for: id, type: type)
        try? data.write(to: url)
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
        try? FileManager.default.removeItem(at: thumbUrl)
        try? FileManager.default.removeItem(at: previewUrl)
    }
}
