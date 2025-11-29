import Foundation
import AppKit
import CoreImage

class RawImageLoader {
    static func loadRaw(url: URL) -> NSImage? {
        // 1. Try Core Image (CIFilter) - Robust for RAWs
        if let filter = CIFilter(imageURL: url, options: nil) {
            if let outputImage = filter.outputImage {
                let context = CIContext()
                if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
                    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                }
            }
        }
        
        // 2. Try NSBitmapImageRep (Direct load)
        if let data = try? Data(contentsOf: url),
           let rep = NSBitmapImageRep(data: data) {
            let nsImage = NSImage(size: rep.size)
            nsImage.addRepresentation(rep)
            return nsImage
        }
        
        // 3. Try CGImageSource (Full Resolution)
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: true,
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096 // Limit max size to avoid memory explosion
            ]
            
            if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
        
        // 4. Try NSImage (Standard)
        if let image = NSImage(contentsOf: url) {
            return image
        }
        
        // 5. Try Embedded Preview Extraction (ExifTool / Binary Scan)
        if let preview = EmbeddedPreviewExtractor.shared.extractPreview(from: url) {
            return preview
        }
        
        return nil
    }
}
