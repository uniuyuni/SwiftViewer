import Foundation
import ImageIO
import CoreGraphics

public struct ExifMetadata: @unchecked Sendable {
    public var cameraMake: String?
    public var cameraModel: String?
    public var lensModel: String?
    public var focalLength: Double?
    public var aperture: Double?
    public var shutterSpeed: String?
    public var iso: Int?
    public var dateTimeOriginal: Date?
    public var width: Int?
    public var height: Int?
    public var orientation: Int?
    public var rating: Int?
    public var colorLabel: String?
    // Extended fields
    public var meteringMode: String?
    public var flash: String?
    public var whiteBalance: String?
    public var exposureProgram: String?
    public var exposureCompensation: Double?
    public var software: String?
    public var rawProps: [String: Any]? // Dictionary for internal use, will be serialized
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
    
    func readExifSync(from url: URL) -> ExifMetadata? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached.metadata
        }
        let metadata = _readExif(from: url)
        if let metadata = metadata {
            cache.setObject(ExifMetadataWrapper(metadata: metadata), forKey: key)
        }
        return metadata
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
    
    static func extractMetadata(from source: CGImageSource) -> ExifMetadata? {
        var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        if properties == nil {
            // Try container properties
            properties = CGImageSourceCopyProperties(source, nil) as? [String: Any]
        }
        
        guard let props = properties else {
            return nil
        }
        
        var metadata = ExifMetadata()
        metadata.rawProps = props
        
        // Basic dimensions and orientation
        let w = props[kCGImagePropertyPixelWidth as String] as? Int
        let h = props[kCGImagePropertyPixelHeight as String] as? Int
        metadata.orientation = props[kCGImagePropertyOrientation as String] as? Int
        
        // Swap dimensions if rotated 90/270 degrees
        if let orient = metadata.orientation, [5, 6, 7, 8].contains(orient) {
            metadata.width = h
            metadata.height = w
        } else {
            metadata.width = w
            metadata.height = h
        }
        
        // TIFF (Camera info)
        if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            metadata.cameraMake = tiff[kCGImagePropertyTIFFMake as String] as? String
            metadata.cameraModel = tiff[kCGImagePropertyTIFFModel as String] as? String
            
            if let dateString = tiff[kCGImagePropertyTIFFDateTime as String] as? String {
                metadata.dateTimeOriginal = ExifReader.shared.parseDate(dateString)
            }
            
            metadata.software = tiff[kCGImagePropertyTIFFSoftware as String] as? String
        }
        
        // IPTC (Rating, etc.)
        if let iptc = props[kCGImagePropertyIPTCDictionary as String] as? [String: Any] {
            metadata.rating = iptc[kCGImagePropertyIPTCStarRating as String] as? Int
            
            if let urgency = iptc[kCGImagePropertyIPTCUrgency as String] as? Int {
                switch urgency {
                case 1: metadata.colorLabel = "Red"
                case 2: metadata.colorLabel = "Orange"
                case 3: metadata.colorLabel = "Yellow"
                case 4: metadata.colorLabel = "Green"
                case 5: metadata.colorLabel = "Blue"
                case 6: metadata.colorLabel = "Purple"
                case 7: metadata.colorLabel = "Gray"
                default: break
                }
            }
        }
        
        // Exif (Shooting info)
        if let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            metadata.focalLength = exif[kCGImagePropertyExifFocalLength as String] as? Double
            metadata.aperture = exif[kCGImagePropertyExifFNumber as String] as? Double
            metadata.iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first
            
            if let shutter = exif[kCGImagePropertyExifExposureTime as String] as? Double {
                metadata.shutterSpeed = ExifReader.shared.formatShutterSpeed(shutter)
            }
            
            if let lens = exif[kCGImagePropertyExifLensModel as String] as? String {
                metadata.lensModel = lens
            }
            
            if let dateString = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                metadata.dateTimeOriginal = ExifReader.shared.parseDate(dateString)
            }
            
            // Extended (CGImageSource)
            metadata.exposureCompensation = exif[kCGImagePropertyExifExposureBiasValue as String] as? Double
        }
        
        return metadata
    }

    private func _readExif(from url: URL) -> ExifMetadata? {
        // 1. Try ExifTool ONLY for RAW files (Performance optimization)
        let ext = url.pathExtension.lowercased()
        let isRaw = FileConstants.allowedImageExtensions.contains(ext) && !["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"].contains(ext)
        
        if isRaw {
            // Force ExifTool for ALL RAW files to ensure correct orientation/dimensions
            // CGImageSource often fails to read the correct Orientation or Dimensions for RAWs.
            if let metadata = readExifUsingExifTool(from: url) {
                return metadata
            }
            print("ExifReader: ExifTool failed for RAW \(url.lastPathComponent). Falling back to CGImageSource.")
        }
        
        // 2. Fallback to CGImageSource (Standard)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            print("ExifReader: CGImageSource creation failed for \(url.path)")
            return nil
        }
        
        return ExifReader.extractMetadata(from: source)
    }
    
    // MARK: - ExifTool Integration
    
    func readExifBatch(from urls: [URL]) async -> [URL: ExifMetadata] {
        guard !urls.isEmpty else { return [:] }
        
        return await Task.detached(priority: .userInitiated) {
            // Split into chunks to avoid command line length limits
            let chunkSize = 50
            var results: [URL: ExifMetadata] = [:]
            
            for chunk in urls.chunked(into: chunkSize) {
                let chunkResults = self.readExifBatchChunk(from: chunk)
                if chunkResults.isEmpty {
                    // Fallback: Read individually if batch fails
                    for url in chunk {
                        if let meta = self.readExifSync(from: url) {
                            results[url] = meta
                        }
                    }
                } else {
                    results.merge(chunkResults) { (_, new) in new }
                }
            }
            
            return results
        }.value
    }
    
    private func readExifBatchChunk(from urls: [URL]) -> [URL: ExifMetadata] {
        log("ExifReader: Reading batch chunk of \(urls.count) files")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/exiftool")
        var args = ["-j", "-struct"] // Use -struct for structured output
        args.append(contentsOf: urls.map { $0.path })
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            guard !data.isEmpty else {
                log("ExifReader: Batch chunk returned empty data")
                return [:]
            }
            
            // Parse as Dictionary instead of Struct for flexibility
            guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
                log("ExifReader: Failed to parse JSON from ExifTool batch output")
                return [:]
            }
            
            var metadataMap: [URL: ExifMetadata] = [:]
            
            for output in json {
                guard let sourceFile = output["SourceFile"] as? String else { continue }
                let url = URL(fileURLWithPath: sourceFile)
                
                var meta = ExifMetadata()
                meta.rawProps = output // Store raw dictionary for debugging/advanced use
                
                // Basic Fields
                meta.cameraMake = output["Make"] as? String
                meta.cameraModel = output["Model"] as? String
                meta.lensModel = output["LensModel"] as? String
                meta.software = output["Software"] as? String
                
                // Focal Length
                if let fl = output["FocalLength"] as? Double {
                    meta.focalLength = fl
                } else if let flStr = output["FocalLength"] as? String {
                    // "10.0 mm" -> 10.0
                    let val = flStr.replacingOccurrences(of: " mm", with: "")
                    meta.focalLength = Double(val)
                }
                
                // Aperture
                if let fn = output["FNumber"] as? Double {
                    meta.aperture = fn
                } else if let fnStr = output["FNumber"] as? String {
                    // "2.8" or "f/2.8"
                    let val = fnStr.replacingOccurrences(of: "f/", with: "")
                    meta.aperture = Double(val)
                }
                
                // Shutter Speed (Keep as String for display, e.g. "1/100")
                if let et = output["ExposureTime"] as? String {
                    meta.shutterSpeed = et
                } else if let et = output["ExposureTime"] as? Double {
                    meta.shutterSpeed = formatShutterSpeed(et)
                }
                
                // ISO
                if let iso = output["ISO"] as? Int {
                    meta.iso = iso
                } else if let isoStr = output["ISO"] as? String {
                    meta.iso = Int(isoStr)
                }
                
                // Dimensions
                let w = (output["RawImageWidth"] as? Int) ?? (output["ExifImageWidth"] as? Int) ?? (output["ImageWidth"] as? Int)
                let h = (output["RawImageHeight"] as? Int) ?? (output["ExifImageHeight"] as? Int) ?? (output["ImageHeight"] as? Int)
                
                // Orientation
                var orient = 1
                if let o = output["Orientation"] as? Int {
                    orient = o
                } else if let oStr = output["Orientation"] as? String {
                    // Parse String: "Horizontal (normal)", "Rotate 90 CW", etc.
                    if oStr.contains("90 CW") { orient = 6 }
                    else if oStr.contains("270 CW") || oStr.contains("90 CCW") { orient = 8 }
                    else if oStr.contains("180") { orient = 3 }
                    else if oStr.contains("Horizontal") { orient = 1 }
                    // Add more if needed, but these are standard
                }
                
                // Swap dimensions if rotated
                if [5, 6, 7, 8].contains(orient) {
                    meta.width = h
                    meta.height = w
                } else {
                    meta.width = w
                    meta.height = h
                }
                meta.orientation = orient
                
                // Date
                if let dateStr = output["DateTimeOriginal"] as? String {
                    meta.dateTimeOriginal = parseDate(dateStr)
                }
                
                // Extended Fields (Strings)
                meta.meteringMode = output["MeteringMode"] as? String
                meta.flash = output["Flash"] as? String
                meta.whiteBalance = output["WhiteBalance"] as? String
                meta.exposureProgram = output["ExposureProgram"] as? String
                meta.exposureCompensation = output["ExposureCompensation"] as? Double
                
                // Rating
                meta.rating = output["Rating"] as? Int
                
                // Label
                if let label = output["Label"] as? String {
                    meta.colorLabel = label
                } else if let urgency = output["Urgency"] as? Int {
                     switch urgency {
                     case 1: meta.colorLabel = "Red"
                     case 2: meta.colorLabel = "Orange"
                     case 3: meta.colorLabel = "Yellow"
                     case 4: meta.colorLabel = "Green"
                     case 5: meta.colorLabel = "Blue"
                     case 6: meta.colorLabel = "Purple"
                     case 7: meta.colorLabel = "Gray"
                     default: break
                     }
                }
                
                metadataMap[url] = meta
            }
            
            return metadataMap
            
        } catch {
            log("ExifReader: Batch chunk failed with error: \(error)")
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

    internal func readExifUsingExifTool(from url: URL) -> ExifMetadata? {
        guard let exifToolPath = getExifToolPath() else {
            log("ExifTool not found")
            return nil
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exifToolPath)
        // Use -n for numeric output, NO -g (flat JSON)
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
            
            if !data.isEmpty {
                // Parse as Dictionary instead of Struct for flexibility
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]],
                   let output = json.first {
                    
                    var meta = ExifMetadata()
                    meta.rawProps = output // Store raw dictionary for debugging/advanced use
                    
                    // Basic Fields
                    meta.cameraMake = output["Make"] as? String
                    meta.cameraModel = output["Model"] as? String
                    meta.lensModel = output["LensModel"] as? String
                    meta.software = output["Software"] as? String
                    
                    // Focal Length
                    if let fl = output["FocalLength"] as? Double {
                        meta.focalLength = fl
                    } else if let flStr = output["FocalLength"] as? String {
                        // "10.0 mm" -> 10.0
                        let val = flStr.replacingOccurrences(of: " mm", with: "")
                        meta.focalLength = Double(val)
                    }
                    
                    // Aperture
                    if let fn = output["FNumber"] as? Double {
                        meta.aperture = fn
                    } else if let fnStr = output["FNumber"] as? String {
                        // "2.8" or "f/2.8"
                        let val = fnStr.replacingOccurrences(of: "f/", with: "")
                        meta.aperture = Double(val)
                    }
                    
                    // Shutter Speed (Keep as String for display, e.g. "1/100")
                    if let et = output["ExposureTime"] as? String {
                        meta.shutterSpeed = et
                    } else if let et = output["ExposureTime"] as? Double {
                        meta.shutterSpeed = formatShutterSpeed(et)
                    }
                    
                    // ISO
                    if let iso = output["ISO"] as? Int {
                        meta.iso = iso
                    } else if let isoStr = output["ISO"] as? String {
                        meta.iso = Int(isoStr)
                    }
                    
                    // Dimensions
                    let w = (output["RawImageWidth"] as? Int) ?? (output["ExifImageWidth"] as? Int) ?? (output["ImageWidth"] as? Int)
                    let h = (output["RawImageHeight"] as? Int) ?? (output["ExifImageHeight"] as? Int) ?? (output["ImageHeight"] as? Int)
                    
                    // Orientation
                    var orient = 1
                    if let o = output["Orientation"] as? Int {
                        orient = o
                    } else if let oStr = output["Orientation"] as? String {
                        // Parse String: "Horizontal (normal)", "Rotate 90 CW", etc.
                        if oStr.contains("90 CW") { orient = 6 }
                        else if oStr.contains("270 CW") || oStr.contains("90 CCW") { orient = 8 }
                        else if oStr.contains("180") { orient = 3 }
                        else if oStr.contains("Horizontal") { orient = 1 }
                    }
                    
                    // Swap dimensions if rotated
                    if [5, 6, 7, 8].contains(orient) {
                        meta.width = h
                        meta.height = w
                    } else {
                        meta.width = w
                        meta.height = h
                    }
                    meta.orientation = orient
                    
                    // Date
                    if let dateStr = output["DateTimeOriginal"] as? String {
                        meta.dateTimeOriginal = parseDate(dateStr)
                    }
                    
                    // Extended Fields (Strings)
                    meta.meteringMode = output["MeteringMode"] as? String
                    meta.flash = output["Flash"] as? String
                    meta.whiteBalance = output["WhiteBalance"] as? String
                    meta.exposureProgram = output["ExposureProgram"] as? String
                    meta.exposureCompensation = output["ExposureCompensation"] as? Double
                    
                    // Rating
                    meta.rating = output["Rating"] as? Int
                    
                    // Label
                    if let label = output["Label"] as? String {
                        meta.colorLabel = label
                    } else if let urgency = output["Urgency"] as? Int {
                         switch urgency {
                         case 1: meta.colorLabel = "Red"
                         case 2: meta.colorLabel = "Orange"
                         case 3: meta.colorLabel = "Yellow"
                         case 4: meta.colorLabel = "Green"
                         case 5: meta.colorLabel = "Blue"
                         case 6: meta.colorLabel = "Purple"
                         case 7: meta.colorLabel = "Gray"
                         default: break
                         }
                    }
                    
                    log("ExifReader: Successfully read metadata for \(url.path). Orientation: \(orient)")
                    return meta
                }
            }
            
            // If data was empty or parsing failed, log it
            log("ExifTool returned empty or unparseable data for \(url.path)")
            return nil
            
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
