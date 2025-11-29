import Foundation
import AppKit

class EmbeddedPreviewExtractor {
    static let shared = EmbeddedPreviewExtractor()
    
    // Known JPEG signatures
    private let jpegStart: [UInt8] = [0xFF, 0xD8]
    private let jpegEnd: [UInt8] = [0xFF, 0xD9]
    
    enum PreviewType {
        case thumbnail
        case preview
    }
    
    func extractThumbnail(from url: URL) -> NSImage? {
        // 1. Try ExifTool with ThumbnailImage
        if let image = extractUsingExifTool(url: url, type: .thumbnail) {
            return image
        }
        // 2. Fallback: Binary Scan (might return large preview, but better than nothing)
        return extractUsingBinaryScan(url: url)
    }
    
    func extractPreview(from url: URL) -> NSImage? {
        // 1. Try ExifTool with PreviewImage/JpgFromRaw
        if let image = extractUsingExifTool(url: url, type: .preview) {
            return image
        }
        // 2. Fallback: Binary Scan
        return extractUsingBinaryScan(url: url)
    }
    
    private func extractUsingExifTool(url: URL, type: PreviewType) -> NSImage? {
        // Check if exiftool exists (simple check, maybe cache this)
        // For now, assume it might be in /usr/local/bin or PATH
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/exiftool") // Hardcoded for now based on check
        
        var args: [String] = ["-b"]
        switch type {
        case .thumbnail:
            args.append("-ThumbnailImage")
        case .preview:
            // Try Composite:PreviewImage first, then JpgFromRaw
            // Note: ExifTool only extracts one tag at a time with -b usually, or concatenates them.
            // We should try one by one or use a specific priority.
            // Let's try Composite:PreviewImage first as it's usually the best.
            // If that fails, we might need another call.
            // For simplicity, let's ask for Composite:PreviewImage.
            // If we want to be robust, we can try multiple tags.
            // But for now, let's use -PreviewImage which is often an alias or Composite.
            args.append("-PreviewImage")
            args.append("-JpgFromRaw") // Fallback if PreviewImage is missing? Exiftool might output both if both present?
            // Actually, if we pass multiple tags with -b, they are concatenated. We don't want that.
            // Let's just try PreviewImage first.
             args = ["-b", "-PreviewImage", url.path]
        }
        
        if type == .thumbnail {
             args.append(url.path)
        }
        
        // Refined Logic for Preview:
        // If type is preview, we really want the largest one.
        // Let's try a prioritized list logic if we were doing this strictly.
        // But for this implementation, let's stick to a simple call.
        // If PreviewImage fails, we might miss JpgFromRaw.
        // Let's try a combined approach: Ask for -JpgFromRaw if -PreviewImage fails?
        // That requires two calls.
        // Let's just use -PreviewImage for now as it's the standard composite tag.
        
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            if !data.isEmpty, let image = NSImage(data: data) {
                return fixOrientation(of: image, from: url)
            } else if type == .preview {
                // Fallback for preview: Try JpgFromRaw
                return extractUsingExifToolTag(url: url, tag: "-JpgFromRaw")
            }
        } catch {
            return nil
        }
        
        return nil
    }
    
    private func extractUsingExifToolTag(url: URL, tag: String) -> NSImage? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/exiftool")
        process.arguments = ["-b", tag, url.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            if !data.isEmpty, let image = NSImage(data: data) {
                return fixOrientation(of: image, from: url)
            }
        } catch {
            return nil
        }
        return nil
    }
    
    func fixOrientation(of image: NSImage, from url: URL) -> NSImage {
        // Read orientation from the ORIGINAL file
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let orientation = properties[kCGImagePropertyOrientation as String] as? Int else {
            return image
        }
        return fixOrientation(of: image, orientation: orientation)
    }
    
    func fixOrientation(of image: NSImage, orientation: Int) -> NSImage {
        // If orientation is 1 (Normal), no need to rotate
        if orientation == 1 { return image }
        
        // Rotate the image
        return rotate(image: image, orientation: orientation)
    }
    
    private func rotate(image: NSImage, orientation: Int) -> NSImage {
        var degrees: CGFloat = 0
        var isMirrored = false
        
        switch orientation {
        case 1: degrees = 0
        case 3: degrees = 180
        case 6: degrees = -90
        case 8: degrees = 90
        case 2: isMirrored = true
        case 4: degrees = 180; isMirrored = true
        case 5: degrees = -90; isMirrored = true
        case 7: degrees = 90; isMirrored = true
        default: return image
        }
        
        // Create a new image with rotation
        // This is a simplified rotation logic using NSImage.lockFocus
        // For better performance/quality, Core Graphics or CIImage is better, but NSImage is easier here.
        
        let newSize = (degrees == 90 || degrees == -90) ? NSSize(width: image.size.height, height: image.size.width) : image.size
        let newImage = NSImage(size: newSize)
        
        newImage.lockFocus()
        
        let context = NSGraphicsContext.current?.cgContext
        context?.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        
        if isMirrored {
            context?.scaleBy(x: -1, y: 1)
        }
        
        context?.rotate(by: degrees * .pi / 180)
        context?.translateBy(x: -image.size.width / 2, y: -image.size.height / 2)
        
        image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        
        newImage.unlockFocus()
        
        return newImage
    }
    
    private func extractUsingBinaryScan(url: URL) -> NSImage? {
        // Read file data (mapped for performance)
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        
        // This is a simplified scanner. 
        // Real RAWs have offsets in header, but parsing every format is hard.
        // We just look for FF D8 ... FF D9 blocks and take the largest one.
        
        var largestData: Data?
        var largestSize: Int = 0
        
        let count = data.count
        // Limit scan to first 10MB or so? Some previews are at the end (Sony ARW).
        
        // Limit scan to first 10MB or so? Some previews are at the end (Sony ARW).
        // Sony ARW: Preview is often near the end or in the middle.
        // Let's scan the whole file but be careful.
        // Scanning 50MB+ in Swift loop might be slow.
        // Optimization: Search for FF D8 using range(of:)
        
        var searchRange = 0..<count
        
        while let startRange = data.range(of: Data(jpegStart), options: [], in: searchRange) {
            let start = startRange.lowerBound
            
            // Look for end tag after start
            // Limit search for end tag to avoid scanning too far? 
            // Previews can be large (10MB+).
            let endSearchStart = start + 2
            let endSearchEnd = min(start + 20_000_000, count) // Max 20MB preview
            
            if endSearchStart >= endSearchEnd { break }
            
            if let endRange = data.range(of: Data(jpegEnd), options: [], in: endSearchStart..<endSearchEnd) {
                let end = endRange.upperBound
                let length = end - start
                
                if length > largestSize {
                    largestSize = length
                    largestData = data.subdata(in: start..<end)
                }
                
                // Continue search after this block
                searchRange = start + 1..<count // Overlap check? or end..<count?
                // Some thumbnails are inside previews?
                // Let's just move forward.
            } else {
                // No end found nearby, move on
                searchRange = start + 1..<count
            }
        }
        
        if let jpegData = largestData, let image = NSImage(data: jpegData) {
            return fixOrientation(of: image, from: url)
        }
        
        return nil
    }
}
