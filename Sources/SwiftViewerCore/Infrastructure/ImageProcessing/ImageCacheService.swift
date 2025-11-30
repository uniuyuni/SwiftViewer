import Foundation
import AppKit

class ImageCacheService {
    static let shared = ImageCacheService()
    
    private let cache = NSCache<NSString, NSImage>()
    
    private init() {
        cache.countLimit = 2000 // Cache up to 2000 images
        cache.totalCostLimit = 500 * 1024 * 1024 // 500 MB
    }
    
    func image(forKey key: String) -> NSImage? {
        return cache.object(forKey: key as NSString)
    }
    
    func setImage(_ image: NSImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
}
