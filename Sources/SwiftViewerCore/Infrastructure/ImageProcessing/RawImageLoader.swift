import Foundation
import AppKit
import CoreImage

class RawImageLoader {
    static func loadRaw(url: URL) -> NSImage? {
        // 0. Check existence first to avoid unnecessary work/errors
        if !FileManager.default.fileExists(atPath: url.path) {
            return nil
        }

        var loadedImage: NSImage?

        // 1. Try Core Image (CIFilter) - Robust for RAWs
        if let filter = CIFilter(imageURL: url, options: nil) {
            if let outputImage = filter.outputImage {
                let context = CIContext()
                if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
                    loadedImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                }
            }
        }
        
        // 2. Try NSBitmapImageRep (Direct load)
        if loadedImage == nil {
            if let data = try? Data(contentsOf: url),
               let rep = NSBitmapImageRep(data: data) {
                let nsImage = NSImage(size: rep.size)
                nsImage.addRepresentation(rep)
                loadedImage = nsImage
            }
        }
        
        // 3. Try CGImageSource (Full Resolution)
        if loadedImage == nil {
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                let options: [CFString: Any] = [
                    kCGImageSourceShouldCache: true,
                    kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                    kCGImageSourceThumbnailMaxPixelSize: 4096 // Limit max size to avoid memory explosion
                ]
                
                if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) {
                    loadedImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                }
            }
        }
        
        // 4. Try NSImage (Standard)
        if loadedImage == nil {
            if let image = NSImage(contentsOf: url) {
                loadedImage = image
            }
        }
        
        // Check if loaded image is too small (e.g. < 2000px long edge)
        // Many RAWs decode to a small embedded thumbnail via CI/CGImageSource if not handled correctly
        if let image = loadedImage {
            let maxDim = max(image.size.width, image.size.height)
            if maxDim < 2000 {
                // Try Embedded Preview Extraction
                if let preview = EmbeddedPreviewExtractor.shared.extractPreview(from: url) {
                    let previewMaxDim = max(preview.size.width, preview.size.height)
                    if previewMaxDim > maxDim {
                        return preview
                    }
                }
            }
            return image
        }
        
        // 5. Try Embedded Preview Extraction (ExifTool / Binary Scan)
        if let preview = EmbeddedPreviewExtractor.shared.extractPreview(from: url) {
            return preview
        }
        
        return nil
    }
}
