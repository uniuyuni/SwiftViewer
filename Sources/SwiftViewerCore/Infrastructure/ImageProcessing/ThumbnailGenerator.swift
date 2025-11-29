import Foundation
import AppKit
import QuickLookThumbnailing

class ThumbnailGenerator {
    static let shared = ThumbnailGenerator()
    private init() {}
    
    struct SendableImage: @unchecked Sendable {
        let image: NSImage?
    }

    func generateThumbnail(for url: URL, size: CGSize, orientation: Int? = nil) async -> NSImage? {
        if Task.isCancelled { return nil }
        
        let key = "\(url.path)_\(Int(size.width))x\(Int(size.height))_v4"
        
        // Check cache (Fast, no await if ImageCacheService is fast)
        if let cached = ImageCacheService.shared.image(forKey: key) {
            return cached
        }
        
        let ext = url.pathExtension.lowercased()
        let isRaw = FileConstants.allowedImageExtensions.contains(ext) && !["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"].contains(ext)
        
        // For RAW files, prioritize CGImageSource to use embedded preview with Manual Rotation
        if isRaw {
            if Task.isCancelled { return nil }
            // Run synchronous downsample in detached task to avoid blocking calling thread
            let thumbWrapper = await Task.detached(priority: .userInitiated) {
                // Use applyTransform: false to get raw sensor data, we will rotate manually in View
                let img = self.downsample(imageAt: url, to: size, applyTransform: false)
                return SendableImage(image: img)
            }.value
            
            if let thumb = thumbWrapper.image {
                ImageCacheService.shared.setImage(thumb, forKey: key)
                return thumb
            }
        }
        
        // Use CGImageSource (downsample) primarily for consistency
        if Task.isCancelled { return nil }
        
        // Primary: CGImageSource
        // Use applyTransform: true for RGB files (JPG, HEIC, etc) as system handles them correctly
        if let downsampled = downsample(imageAt: url, to: size, applyTransform: true) {
            ImageCacheService.shared.setImage(downsampled, forKey: key)
            return downsampled
        }
        
        // Fallback: NSImage
        if let image = NSImage(contentsOf: url) {
             ImageCacheService.shared.setImage(image, forKey: key)
             return image
        }
        
        // Final Fallback: Embedded Thumbnail Extraction
        Logger.shared.log("DEBUG: ThumbnailGenerator falling back to EmbeddedPreviewExtractor for \(url.lastPathComponent)")
        let thumbWrapper = await Task.detached(priority: .utility) {
            let img = EmbeddedPreviewExtractor.shared.extractThumbnail(from: url)
            return SendableImage(image: img)
        }.value
        
        if let thumb = thumbWrapper.image {
            ImageCacheService.shared.setImage(thumb, forKey: key)
            return thumb
        }
        
        return nil
    }
    
    private func downsample(imageAt imageURL: URL, to pointSize: CGSize, scale: CGFloat = 2.0, applyTransform: Bool = true) -> NSImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, imageSourceOptions) else { return nil }
        
        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: applyTransform,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary
        
        if let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) {
            return NSImage(cgImage: downsampledImage, size: NSSize(width: CGFloat(downsampledImage.width), height: CGFloat(downsampledImage.height)))
        }
        
        return nil
    }
}
