import Foundation
import SwiftUI

class ThumbnailCacheService {
    static let shared = ThumbnailCacheService()
    
    private let cacheDirectory: URL
    
    private init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("SwiftViewer")
        cacheDirectory = appSupport.appendingPathComponent("Thumbnails")
        
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func cachePath(for id: UUID) -> URL {
        return cacheDirectory.appendingPathComponent(id.uuidString + ".jpg")
    }
    
    func saveThumbnail(image: NSImage, for id: UUID) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return }
        
        let url = cachePath(for: id)
        try? data.write(to: url)
    }
    
    func loadThumbnail(for id: UUID) -> NSImage? {
        let url = cachePath(for: id)
        return NSImage(contentsOf: url)
    }
    
    func hasThumbnail(for id: UUID) -> Bool {
        return FileManager.default.fileExists(atPath: cachePath(for: id).path)
    }
    
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
