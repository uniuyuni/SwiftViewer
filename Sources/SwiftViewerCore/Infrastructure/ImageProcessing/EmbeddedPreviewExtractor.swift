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
        let exifToolPath = "/usr/local/bin/exiftool"
        guard FileManager.default.fileExists(atPath: exifToolPath) else { return nil }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exifToolPath)
        
        var args: [String] = ["-b"]
        switch type {
        case .thumbnail:
            args.append("-ThumbnailImage")
            args.append(url.path)
        case .preview:
            // For RAF, use PreviewImage (usually full size or large preview)
            if url.pathExtension.lowercased() == "raf" {
                args.append("-PreviewImage")
                args.append(url.path)
            } else {
                // Try PreviewImage first for others
                args.append("-PreviewImage")
                args.append(url.path)
            }
        }
        
        process.arguments = args
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            if !data.isEmpty, let image = NSImage(data: data) {
                return fixOrientation(of: image, from: data, url: url)
            } else {
                // If PreviewImage failed, try JpgFromRaw for previews (or PreviewImage if we tried JpgFromRaw first)
                if type == .preview {
                    let ext = url.pathExtension.lowercased()
                    let tag = (ext == "raf") ? "-JpgFromRaw" : "-JpgFromRaw"
                    print("DEBUG: ExifTool primary tag failed for \(url.lastPathComponent), trying \(tag)")
                    return extractUsingExifToolTag(url: url, tag: tag)
                }
                
                // Log error if needed
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if let errorStr = String(data: errorData, encoding: .utf8), !errorStr.isEmpty {
                    print("DEBUG: ExifTool error for \(url.lastPathComponent): \(errorStr)")
                }
            }
        } catch {
            print("DEBUG: ExifTool execution failed: \(error)")
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
                return fixOrientation(of: image, from: data, url: url)
            }
        } catch {
            return nil
        }
        return nil
    }
    
    func fixOrientation(of image: NSImage, from data: Data, url: URL) -> NSImage {
        let orientation = getOrientation(from: data, url: url)
        return fixOrientation(of: image, orientation: orientation)
    }
    
    private func getOrientation(from data: Data, url: URL) -> Int {
        let ext = url.pathExtension.lowercased()
        
        // RAF Fix: Force Orient 1 for Portrait RAWs to match User preference
        if ext == "raf" {
            print("DEBUG: RAF detected. Forcing Orient 1 (Portrait).")
            return 1
        }
        
        // 1. Try Embedded Data Orientation
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let orientation = properties[kCGImagePropertyOrientation as String] as? Int {
            return orientation
        }
        
        // 2. Exceptions (Ignore RAW Orientation)
        if ext == "orf" {
            // Olympus ORF embedded previews are often already rotated or don't match RAW tag
            return 1
        }
        
        // 3. Special Handling for Sony ARW
        if ext == "arw" {
            // Try Sony:CameraOrientation via ExifTool
            if let sonyOrient = getExifToolTag(url: url, tag: "-Sony:CameraOrientation") {
                return sonyOrient
            }
        }
        
        // 4. Fallback: RAW File Orientation
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let orientation = properties[kCGImagePropertyOrientation as String] as? Int {
            
            return orientation
        }
        
        return 1
    }
    
    private func getExifToolTag(url: URL, tag: String) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/exiftool")
        process.arguments = ["-b", "-n", tag, url.path] // -n for numeric
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let val = Int(str) {
                return val
            }
        } catch {
            return nil
        }
        return nil
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
        case 6: degrees = 90 // 90 CW (Needs -90 radians in CGContext? No, wait.)
            // CGContext rotate(by: angle) -> positive is CCW.
            // Orient 6 (Right Top) -> Needs 90 CW rotation to be Upright.
            // 90 CW = -90 CCW.
            // context.rotate(by: -radians).
            // If degrees = 90, radians = 90. rotate(by: -90) -> 90 CW. Correct.
        case 8: degrees = -90 // 90 CCW (Needs 90 radians in CGContext)
            // Orient 8 (Left Bottom) -> Needs 90 CCW rotation to be Upright.
            // 90 CCW = 90 CCW.
            // context.rotate(by: -radians).
            // If degrees = -90, radians = -90. rotate(by: -(-90)) = rotate(by: 90) -> 90 CCW. Correct.
        case 2: isMirrored = true
        case 4: degrees = 180; isMirrored = true
        case 5: degrees = -90; isMirrored = true
        case 7: degrees = 90; isMirrored = true
        default: return image
        }
        
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        
        let originalWidth = CGFloat(cgImage.width)
        let originalHeight = CGFloat(cgImage.height)
        
        let radians = degrees * .pi / 180
        let absRadians = abs(radians)
        
        let cosVal = abs(cos(absRadians))
        let sinVal = abs(sin(absRadians))
        
        print("DEBUG: rotate(orient: \(orientation)) -> degrees: \(degrees), radians: \(radians)")
        print("DEBUG: Original: \(originalWidth)x\(originalHeight)")
        print("DEBUG: cos: \(cosVal), sin: \(sinVal)")
        
        let newWidth = originalWidth * cosVal + originalHeight * sinVal
        let newHeight = originalWidth * sinVal + originalHeight * cosVal
        
        print("DEBUG: Calculated New Size: \(newWidth)x\(newHeight)")
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(data: nil,
                                      width: Int(newWidth),
                                      height: Int(newHeight),
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            print("DEBUG: rotate failed to create CGContext")
            return image
        }
        
        context.interpolationQuality = .high
        
        context.translateBy(x: newWidth / 2, y: newHeight / 2)
        if isMirrored {
            context.scaleBy(x: -1, y: 1)
        }
        context.rotate(by: -radians)
        
        context.translateBy(x: -originalWidth / 2, y: -originalHeight / 2)
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: originalWidth, height: originalHeight))
        
        guard let newCGImage = context.makeImage() else {
            print("DEBUG: rotate failed to makeImage")
            return image
        }
        
        print("DEBUG: rotate success. New Size: \(newWidth)x\(newHeight)")
        return NSImage(cgImage: newCGImage, size: NSSize(width: newWidth, height: newHeight))
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
            } else {
                // No end found nearby, move on
                searchRange = start + 1..<count
            }
        }
        
        if let jpegData = largestData, let image = NSImage(data: jpegData) {
            return fixOrientation(of: image, from: jpegData, url: url)
        }
        
        return nil
    }
}
