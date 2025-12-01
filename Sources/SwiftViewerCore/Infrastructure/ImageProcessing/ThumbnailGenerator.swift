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
                // Use applyTransform: true to get correct orientation
                let img = self.downsample(imageAt: url, to: size, applyTransform: true)
                return SendableImage(image: img)
            }.value
            
            if let thumb = thumbWrapper.image {
                // Check if the generated image is smaller than requested
                // Use longest edge comparison to handle aspect ratios correctly
                let thumbLongEdge = max(thumb.size.width, thumb.size.height)
                let targetLongEdge = max(size.width, size.height)
                
                // If generated image is significantly smaller (e.g. < 90% of target), try fallback
                // This handles cases where CGImageSource returns a small embedded thumbnail (e.g. 640px) instead of full preview
                let isTooSmall = thumbLongEdge < targetLongEdge * 0.9
                
                if isTooSmall {
                    print("DEBUG: Generated thumbnail for \(url.lastPathComponent) is too small (\(thumb.size) vs \(size)). LongEdge: \(thumbLongEdge) vs \(targetLongEdge). Trying EmbeddedPreviewExtractor.")
                    let largePreviewWrapper = await Task.detached(priority: .userInitiated) {
                        let img = EmbeddedPreviewExtractor.shared.extractPreview(from: url)
                        return SendableImage(image: img)
                    }.value
                    
                    if let largePreview = largePreviewWrapper.image {
                        print("DEBUG: EmbeddedPreviewExtractor returned image size: \(largePreview.size) for \(url.lastPathComponent)")
                        // Resize to target size if needed
                        // Embedded preview might be full size (e.g. 6000x4000), but we want 'size' (e.g. 1024x1024)
                        if let resized = self.resize(image: largePreview, to: size) {
                             print("DEBUG: Resized embedded preview to \(resized.size) for \(url.lastPathComponent)")
                             ImageCacheService.shared.setImage(resized, forKey: key)
                             return resized
                        } else {
                            print("DEBUG: Failed to resize embedded preview for \(url.lastPathComponent)")
                        }
                        
                        var finalImage = largePreview
                        if let orientation = orientation {
                            if let rotated = self.rotate(image: finalImage, orientation: orientation) {
                                finalImage = rotated
                            }
                        }
                        
                        ImageCacheService.shared.setImage(finalImage, forKey: key)
                        return finalImage
                    } else {
                        print("DEBUG: EmbeddedPreviewExtractor returned NIL for \(url.lastPathComponent)")
                    }
                } else {
                     print("DEBUG: Generated thumbnail size \(thumb.size) is acceptable for target \(size).")
                }
                
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
        
        if var thumb = thumbWrapper.image {
            if let orientation = orientation {
                if let rotated = rotate(image: thumb, orientation: orientation) {
                    thumb = rotated
                }
            }
            ImageCacheService.shared.setImage(thumb, forKey: key)
            return thumb
        }
        
        return nil
    }
    
    func generateThumbnailAndMetadataSync(for url: URL, size: CGSize) -> (NSImage?, ExifMetadata?) {
        let key = "\(url.path)_\(Int(size.width))x\(Int(size.height))_v4"
        
        // Check cache for image
        let cachedImage = ImageCacheService.shared.image(forKey: key)
        
        // If image is cached, we still might need metadata if it's not in DB.
        // But ThumbnailGenerationService only calls this if it needs to generate thumbnail OR check metadata?
        // Actually, if image is cached, we return it. Metadata might be skipped.
        // But we want to ensure metadata is extracted.
        // If we return (cachedImage, nil), the service won't update metadata.
        // So we should probably extract metadata even if image is cached?
        // Reading metadata is fast.
        // But if we have thousands of files, reading all is slow.
        // The service should only call this if it needs to.
        
        var image: NSImage? = cachedImage
        var metadata: ExifMetadata? = nil
        
        let ext = url.pathExtension.lowercased()
        let isRaw = FileConstants.allowedImageExtensions.contains(ext) && !["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"].contains(ext)
        
        // Create Source
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, imageSourceOptions) else {
             return (image, nil)
        }
        
        // Extract Metadata
        metadata = ExifReader.extractMetadata(from: imageSource)
        
        // RAW: Use ExifTool for reliable metadata (especially Orientation)
        // Always try ExifTool for RAWs, even if image is cached, because CoreGraphics metadata is often incomplete for RAWs.
        if isRaw {
            if let exifToolMeta = ExifReader.shared.readExifUsingExifTool(from: url) {
                metadata = exifToolMeta
            }
        }
        
        // Generate Thumbnail if needed
        if image == nil {
            if isRaw {
                // Try with applyTransform: true first to get correct orientation
                if let img = downsample(imageAt: url, to: size, applyTransform: true) {
                    image = img
                    ImageCacheService.shared.setImage(img, forKey: key)
                }
            } else {
                // RGB
                if let img = downsample(imageAt: url, to: size, applyTransform: true) {
                    image = img
                    ImageCacheService.shared.setImage(img, forKey: key)
                } else if let img = NSImage(contentsOf: url) {
                    image = img
                    ImageCacheService.shared.setImage(img, forKey: key)
                }
            }
        }
        
        // Check if generated image is too small for RAWs OR if generation failed (Fallback Logic)
        if isRaw {
            var shouldFallback = false
            
            if let img = image {
                let thumbLongEdge = max(img.size.width, img.size.height)
                let targetLongEdge = max(size.width, size.height)
                
                // If generated image is significantly smaller (e.g. < 90% of target), try fallback
                if thumbLongEdge < targetLongEdge * 0.9 {
                    shouldFallback = true
                }
            } else {
                shouldFallback = true
            }
            
            if shouldFallback {
                if let largePreview = EmbeddedPreviewExtractor.shared.extractPreview(from: url) {
                    if let resized = resize(image: largePreview, to: size) {
                        image = resized
                        ImageCacheService.shared.setImage(resized, forKey: key)
                    } else {
                        // Use full size if resize fails
                        // Use full size if resize fails
                        image = largePreview
                        
                        // Rotate if needed (we don't have orientation passed here? We do have metadata!)
                        // But wait, generateThumbnailAndMetadataSync doesn't take orientation arg.
                        // It extracts metadata.
                        // So we should use the extracted metadata orientation!
                        if let meta = metadata, let orientation = meta.orientation {
                             if let rotated = rotate(image: largePreview, orientation: orientation) {
                                 image = rotated
                             }
                        }
                        
                        ImageCacheService.shared.setImage(image!, forKey: key)
                    }
                }
            }
        }
        
        return (image, metadata)
    }

    func generateThumbnailSync(for url: URL, size: CGSize) -> NSImage? {
        return generateThumbnailAndMetadataSync(for: url, size: size).0
    }

    private func downsample(imageAt imageURL: URL, to pointSize: CGSize, scale: CGFloat = 1.0, applyTransform: Bool = true) -> NSImage? {
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
    
    private func resize(image: NSImage, to targetSize: CGSize) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("DEBUG: Resize failed - could not get CGImage from NSImage")
            return nil
        }
        
        let widthRatio = targetSize.width / CGFloat(cgImage.width)
        let heightRatio = targetSize.height / CGFloat(cgImage.height)
        let scale = min(widthRatio, heightRatio)
        
        let newWidth = Int(CGFloat(cgImage.width) * scale)
        let newHeight = Int(CGFloat(cgImage.height) * scale)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(data: nil,
                                      width: newWidth,
                                      height: newHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            print("DEBUG: Resize failed - could not create CGContext")
            return nil
        }
        
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        
        guard let newCGImage = context.makeImage() else {
            print("DEBUG: Resize failed - could not create image from context")
            return nil
        }
        
        return NSImage(cgImage: newCGImage, size: NSSize(width: newWidth, height: newHeight))
    }
    
    private func rotate(image: NSImage, orientation: Int) -> NSImage? {
        var degrees: CGFloat = 0
        switch orientation {
        case 3, 4: degrees = 180
        case 6, 5: degrees = -90 // Right -> Rotate Clockwise 90? No, CG coords are different.
            // EXIF 6 (Right Top) means the 0th row is visual right side. We need to rotate 90 CW?
            // Let's stick to standard mapping.
            // 6: 90 CW (or -90 CCW?)
            // In AsyncThumbnailView we used: 6 -> 90 degrees.
            // Here we rotate the IMAGE.
            degrees = -90 // 90 CW
        case 8, 7: degrees = 90 // 90 CCW
        default: return image
        }
        
        // If 0, return
        if degrees == 0 { return image }
        
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        let radians = degrees * .pi / 180
        
        var newSize = CGRect(origin: .zero, size: image.size).applying(CGAffineTransform(rotationAngle: radians)).integral.size
        // Swap for 90/270
        if abs(degrees) == 90 {
            newSize = CGSize(width: image.size.height, height: image.size.width)
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(data: nil,
                                      width: Int(newSize.width),
                                      height: Int(newSize.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else { return nil }
        
        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        context.rotate(by: radians)
        context.translateBy(x: -image.size.width / 2, y: -image.size.height / 2)
        
        context.draw(cgImage, in: CGRect(origin: .zero, size: image.size))
        
        guard let newCGImage = context.makeImage() else { return nil }
        return NSImage(cgImage: newCGImage, size: newSize)
    }
}
