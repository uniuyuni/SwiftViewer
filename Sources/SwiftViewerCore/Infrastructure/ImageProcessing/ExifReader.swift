import Foundation
import ImageIO
import CoreGraphics

struct ExifMetadata {
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var focalLength: Double?
    var aperture: Double?
    var shutterSpeed: String?
    var iso: Int?
    var dateTimeOriginal: Date?
    var width: Int?
    var height: Int?
    var orientation: Int?
    var rating: Int?
    var colorLabel: String?
    // Extended fields
    var meteringMode: String?
    var flash: String?
    var whiteBalance: String?
    var exposureProgram: String?
    var exposureCompensation: Double?
    var software: String?
    var rawProps: [String: Any]? // Dictionary for internal use, will be serialized
}

class ExifReader {
    static let shared = ExifReader()
    
    private let cache = NSCache<NSString, ExifMetadataWrapper>()
    
    private init() {}
    
    private func log(_ message: String) {
        // Use a fixed path in Documents for debugging
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let logFileURL = documents.appendingPathComponent("SwiftViewer_Log.txt")
        
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)\n"
        
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
    
    func invalidateCache(for url: URL) {
        let key = url.path as NSString
        cache.removeObject(forKey: key)
    }
    
    func readExif(from url: URL) async -> ExifMetadata? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached.metadata
        }
        
        return await Task.detached(priority: .userInitiated) {
            let metadata = self._readExif(from: url)
            if let metadata = metadata {
                self.cache.setObject(ExifMetadataWrapper(metadata: metadata), forKey: key)
            }
            return metadata
        }.value
    }
    
    func readOrientation(from url: URL) async -> Int? {
        // Fast path: Check cache first
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached.metadata.orientation
        }
        
        return await Task.detached(priority: .userInitiated) {
            // Fast path: Use CGImageSource directly (avoid ExifTool)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            
            // Helper to extract orientation from properties
            func extractOrientation(_ props: [String: Any]) -> Int? {
                // 1. Standard Orientation
                if let orientation = props[kCGImagePropertyOrientation as String] as? Int {
                    return orientation
                }
                // 2. TIFF Orientation
                if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
                   let orientation = tiff[kCGImagePropertyTIFFOrientation as String] as? Int {
                    return orientation
                }
                // 3. IPTC Orientation
                if let iptc = props[kCGImagePropertyIPTCDictionary as String] as? [String: Any],
                   let orientation = iptc[kCGImagePropertyIPTCImageOrientation as String] as? Int {
                    return orientation
                }
                return nil
            }
            
            // Try properties at index 0
            if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
               let orientation = extractOrientation(props) {
                return orientation
            }
            
            // Try container properties
            if let props = CGImageSourceCopyProperties(source, nil) as? [String: Any],
               let orientation = extractOrientation(props) {
                return orientation
            }
            
            // Fallback: Try ExifTool for RAW files if CGImageSource failed
            let ext = url.pathExtension.lowercased()
            let isRaw = FileConstants.allowedImageExtensions.contains(ext) && !["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"].contains(ext)
            
            if isRaw {
                if let metadata = self.readExifUsingExifTool(from: url) {
                    return metadata.orientation
                }
            }
            
            // Fallback: Try MDItem (Spotlight Metadata) - Very fast and system-native
            if let mdItem = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
               let orientation = MDItemCopyAttribute(mdItem, kMDItemOrientation) as? Int {
                return orientation
            }
            
            return nil
        }.value
    }
    
    private func _readExif(from url: URL) -> ExifMetadata? {
        // 1. Try ExifTool ONLY for RAW files (Performance optimization)
        let ext = url.pathExtension.lowercased()
        let isRaw = FileConstants.allowedImageExtensions.contains(ext) && !["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"].contains(ext)
        
        if isRaw {
            if let metadata = readExifUsingExifTool(from: url) {
                return metadata
            }
        }
        
        // 2. Fallback to CGImageSource (Standard)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            print("ExifReader: CGImageSource creation failed for \(url.path)")
            return nil
        }
        
        var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        if properties == nil {
            // Try container properties
            properties = CGImageSourceCopyProperties(source, nil) as? [String: Any]
        }
        
        guard let props = properties else {
            print("ExifReader: No properties found for \(url.path)")
            return nil
        }
        
        var metadata = ExifMetadata()
        metadata.rawProps = props
        
        // Basic dimensions
        metadata.width = props[kCGImagePropertyPixelWidth as String] as? Int
        metadata.height = props[kCGImagePropertyPixelHeight as String] as? Int
        metadata.orientation = props[kCGImagePropertyOrientation as String] as? Int
        
        // Swap dimensions if rotated 90/270 degrees
        if let orientation = metadata.orientation, [5, 6, 7, 8].contains(orientation) {
            let w = metadata.width
            metadata.width = metadata.height
            metadata.height = w
        }
        
        // TIFF (Camera info)
        if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            metadata.cameraMake = tiff[kCGImagePropertyTIFFMake as String] as? String
            metadata.cameraModel = tiff[kCGImagePropertyTIFFModel as String] as? String
            
            if let dateString = tiff[kCGImagePropertyTIFFDateTime as String] as? String {
                metadata.dateTimeOriginal = parseDate(dateString)
            }
            
            metadata.software = tiff[kCGImagePropertyTIFFSoftware as String] as? String
        }
        
        // IPTC (Rating, etc.)
        if let iptc = props[kCGImagePropertyIPTCDictionary as String] as? [String: Any] {
            metadata.rating = iptc[kCGImagePropertyIPTCStarRating as String] as? Int
        }
        
        // Exif (Shooting info)
        if let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            metadata.focalLength = exif[kCGImagePropertyExifFocalLength as String] as? Double
            metadata.aperture = exif[kCGImagePropertyExifFNumber as String] as? Double
            metadata.iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first
            
            if let shutter = exif[kCGImagePropertyExifExposureTime as String] as? Double {
                metadata.shutterSpeed = formatShutterSpeed(shutter)
            }
            
            if let lens = exif[kCGImagePropertyExifLensModel as String] as? String {
                metadata.lensModel = lens
            }
            
            if let dateString = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                metadata.dateTimeOriginal = parseDate(dateString)
            }
            
            // Extended (CGImageSource)
            metadata.exposureCompensation = exif[kCGImagePropertyExifExposureBiasValue as String] as? Double
        }
        
        return metadata
    }
    
    // MARK: - ExifTool Integration
    
    private struct ExifToolOutput: Decodable {
        let SourceFile: String?
        let Make: String?
        let Model: String?
        let LensModel: String?
        let FocalLength: Double?
        let FNumber: Double?
        let ExposureTime: Double?
        let ISO: Int?
        let DateTimeOriginal: String?
        let ImageWidth: Int?
        let ImageHeight: Int?
        let RawImageWidth: Int?
        let RawImageHeight: Int?
        let ExifImageWidth: Int?
        let ExifImageHeight: Int?
        let Orientation: Int?
        let Rating: Int?
        // Extended
        let MeteringMode: Int?
        let Flash: Int?
        let WhiteBalance: Int?
        let ExposureProgram: Int?
        let ExposureCompensation: Double?
        let Software: String?
    }
    
    func readExifBatch(from urls: [URL]) async -> [URL: ExifMetadata] {
        guard !urls.isEmpty else { return [:] }
        
        return await Task.detached(priority: .userInitiated) {
            // Split into chunks to avoid command line length limits
            let chunkSize = 50
            var results: [URL: ExifMetadata] = [:]
            
            for chunk in urls.chunked(into: chunkSize) {
                let chunkResults = self.readExifBatchChunk(from: chunk)
                results.merge(chunkResults) { (_, new) in new }
            }
            
            return results
        }.value
    }
    
    private func readExifBatchChunk(from urls: [URL]) -> [URL: ExifMetadata] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/exiftool")
        var args = ["-j", "-n"]
        args.append(contentsOf: urls.map { $0.path })
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            guard !data.isEmpty else { return [:] }
            
            let decoder = JSONDecoder()
            let outputs = try decoder.decode([ExifToolOutput].self, from: data)
            
            var metadataMap: [URL: ExifMetadata] = [:]
            
            for output in outputs {
                guard let sourceFile = output.SourceFile else { continue }
                let url = URL(fileURLWithPath: sourceFile)
                
                var meta = ExifMetadata()
                meta.cameraMake = output.Make
                meta.cameraModel = output.Model
                meta.lensModel = output.LensModel
                meta.focalLength = output.FocalLength
                meta.aperture = output.FNumber
                if let shutter = output.ExposureTime {
                    meta.shutterSpeed = formatShutterSpeed(shutter)
                }
                meta.iso = output.ISO
                
                // Prefer RAW dimensions, then EXIF, then Image
                meta.width = output.RawImageWidth ?? output.ExifImageWidth ?? output.ImageWidth
                meta.height = output.RawImageHeight ?? output.ExifImageHeight ?? output.ImageHeight
                
                meta.orientation = output.Orientation
                meta.rating = output.Rating
                
                // Extended
                if let mm = output.MeteringMode { meta.meteringMode = String(mm) }
                if let fl = output.Flash { meta.flash = String(fl) }
                if let wb = output.WhiteBalance { meta.whiteBalance = String(wb) }
                if let ep = output.ExposureProgram { meta.exposureProgram = String(ep) }
                if let ep = output.ExposureProgram { meta.exposureProgram = String(ep) }
                meta.exposureCompensation = output.ExposureCompensation
                meta.software = output.Software
                
                if let dateString = output.DateTimeOriginal {
                    meta.dateTimeOriginal = parseDate(dateString)
                }
                
                metadataMap[url] = meta
            }
            
            return metadataMap
            
        } catch {
            return [:]
        }
    }
    
    private func getExifToolPath() -> String? {
        let paths = ["/usr/local/bin/exiftool", "/opt/homebrew/bin/exiftool", "/usr/bin/exiftool", "/opt/local/bin/exiftool"]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Fallback: Try `which exiftool`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["exiftool"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
             return path
        }
        
        return nil
    }

    private func readExifUsingExifTool(from url: URL) -> ExifMetadata? {
        guard let exifToolPath = getExifToolPath() else {
            log("ExifTool not found")
            return nil
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exifToolPath)
        process.arguments = ["-j", "-n", url.path]
        process.environment = ProcessInfo.processInfo.environment // Inherit environment (PATH, etc.)
        
        let pipe = Pipe()
        let errorPipe = Pipe() // Capture stderr
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            if !errorData.isEmpty {
                if let errorString = String(data: errorData, encoding: .utf8) {
                    log("ExifTool stderr for \(url.path): \(errorString)")
                }
            }
            
            if data.isEmpty {
                log("ExifTool returned empty data for \(url.path)")
                return nil
            }
            
            // Debug: Print raw JSON
            if let jsonString = String(data: data, encoding: .utf8) {
                log("ExifTool Raw JSON for \(url.path): \(jsonString)")
            }
            
            let decoder = JSONDecoder()
            let outputs = try decoder.decode([ExifToolOutput].self, from: data)
            
            guard let output = outputs.first else {
                log("ExifTool decoded empty array for \(url.path)")
                return nil
            }
            
            var meta = ExifMetadata()
            // ... (rest of mapping)
            meta.cameraMake = output.Make
            meta.cameraModel = output.Model
            meta.lensModel = output.LensModel
            meta.focalLength = output.FocalLength
            meta.aperture = output.FNumber
            if let shutter = output.ExposureTime {
                meta.shutterSpeed = formatShutterSpeed(shutter)
            }
            meta.iso = output.ISO
            
            // Prefer RAW dimensions
            meta.width = output.RawImageWidth ?? output.ExifImageWidth ?? output.ImageWidth
            meta.height = output.RawImageHeight ?? output.ExifImageHeight ?? output.ImageHeight
            
            meta.orientation = output.Orientation
            meta.rating = output.Rating
            
            // Swap dimensions if rotated 90/270 degrees
            if let orientation = meta.orientation, [5, 6, 7, 8].contains(orientation) {
                let w = meta.width
                meta.width = meta.height
                meta.height = w
            }
            
            // Extended
            if let mm = output.MeteringMode { meta.meteringMode = String(mm) }
            if let fl = output.Flash { meta.flash = String(fl) }
            if let wb = output.WhiteBalance { meta.whiteBalance = String(wb) }
            if let ep = output.ExposureProgram { meta.exposureProgram = String(ep) }
            if let ep = output.ExposureProgram { meta.exposureProgram = String(ep) }
            meta.exposureCompensation = output.ExposureCompensation
            meta.software = output.Software
            
            if let dateString = output.DateTimeOriginal {
                meta.dateTimeOriginal = parseDate(dateString)
            }
            
            log("ExifReader: Successfully read metadata for \(url.path). Orientation: \(meta.orientation ?? -1)")
            return meta
            
        } catch {
            log("ExifTool failed: \(error)")
            return nil
        }
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: dateString)
    }
    
    private func formatShutterSpeed(_ time: Double) -> String {
        if time >= 1 {
            return String(format: "%.1f\"", time)
        } else {
            let denominator = Int(round(1.0 / time))
            return "1/\(denominator)"
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

class ExifMetadataWrapper {
    let metadata: ExifMetadata
    init(metadata: ExifMetadata) {
        self.metadata = metadata
    }
}
