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
    public var isFavorite: Bool?
    public var flagStatus: Int?
    // Extended fields
    public var meteringMode: String?
    public var flash: String?
    public var whiteBalance: String?
    public var exposureProgram: String?
    public var exposureCompensation: Double?
    public var software: String?
    public var brightnessValue: Double?
    public var exposureBias: Double?
    public var serialNumber: String?
    public var title: String?
    public var caption: String?
    public var latitude: Double?
    public var longitude: Double?
    public var altitude: Double?
    public var imageDirection: Double?
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
        // 1. Try ExifTool for ALL files (Robustness over speed)
        // This ensures we get all extended metadata (Software, Metering, etc.) and XMP ratings
        if let metadata = readExifUsingExifTool(from: url) {
            return metadata
        }
        
        // 2. Fallback to CGImageSource if ExifTool fails or is missing
        print("ExifReader: ExifTool failed or missing for \(url.lastPathComponent). Falling back to CGImageSource.")
        
        // 2. Fallback to CGImageSource (Standard)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            print("ExifReader: CGImageSource creation failed for \(url.path)")
            return nil
        }
        
        return ExifReader.extractMetadata(from: source)
    }
    
    // MARK: - ExifTool Integration
    
    // Explicitly list tags to ensure consistent behavior (Numeric vs String)
    private let exifTags = [
        "-Make", "-Model", "-LensModel", "-Software",
        "-FocalLength#", "-FNumber#", "-ExposureTime#", "-ISO#", // Numeric for calculations
        "-ShutterSpeed#", "-Aperture#", // Composite tags for robustness
        "-DateTimeOriginal",
        "-RawImageWidth#", "-RawImageHeight#", "-ExifImageWidth#", "-ExifImageHeight#", "-ImageWidth#", "-ImageHeight#", // Numeric for dimensions
        "-Orientation#", // Numeric for robust rotation logic
        "-MeteringMode", "-Metering", // Metering
        "-Flash", // Flash
        "-WhiteBalance", "-Balance", // White Balance
        "-ExposureProgram", "-ExposureMode", "-ShootingMode", "-CreativeStyle", // Program/Mode
        "-ExposureCompensation#", // Strings for display (except ExpComp)
        "-BrightnessValue#", "-ExposureBiasValue#", // Brightness/Bias
        "-SerialNumber", "-BodySerialNumber", // Serial
        "-Title", "-XMP:Title", "-ObjectName", // Title
        "-Caption", "-Description", "-XMP:Description", "-ImageDescription", "-Caption-Abstract", // Caption
        "-GPSLatitude#", "-GPSLongitude#", "-GPSAltitude#", "-GPSImgDirection#", // GPS
        "-Rating", "-Label", "-Urgency",
        "-XMP:Rating", "-XMP:Label" // Explicitly check XMP
    ]
    
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
        
        guard let exifToolPath = getExifToolPath() else {
            log("ExifReader: ExifTool not found for batch read")
            return [:]
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exifToolPath)
        var args = ["-j", "-struct"]
        args.append(contentsOf: exifTags) // Use explicit tags
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
                
                let meta = parseExifToolOutput(output)
                metadataMap[url] = meta
            }
            
            return metadataMap
            
        } catch {
            log("ExifReader: Batch chunk failed with error: \(error)")
            return [:]
        }
    }
    
    private func getExifToolPath() -> String? {
        // 1. Check standard locations
        let paths = ["/usr/local/bin/exiftool", "/opt/homebrew/bin/exiftool", "/usr/bin/exiftool", "/opt/local/bin/exiftool"]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // 2. Check PATH environment variable
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            let searchPaths = pathEnv.components(separatedBy: ":")
            for searchPath in searchPaths {
                let fullPath = (searchPath as NSString).appendingPathComponent("exiftool")
                if FileManager.default.fileExists(atPath: fullPath) {
                    return fullPath
                }
            }
        }
        
        // 3. Fallback: Try `which exiftool`
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
        
        print("ExifReader: ExifTool NOT found in standard paths or PATH.")
        return nil
    }

    internal func readExifUsingExifTool(from url: URL) -> ExifMetadata? {
        guard let exifToolPath = getExifToolPath() else {
            log("ExifTool not found")
            return nil
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exifToolPath)
        // Use explicit tags, NO -n (since we use # suffixes), NO -g
        var args = ["-j"]
        args.append(contentsOf: exifTags)
        args.append(url.path)
        process.arguments = args
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
                    
                    let meta = parseExifToolOutput(output)
                    log("ExifReader: Successfully read metadata for \(url.path). Orientation: \(meta.orientation ?? -1)")
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
    
    private func parseExifToolOutput(_ output: [String: Any]) -> ExifMetadata {
        var meta = ExifMetadata()
        meta.rawProps = output
        
        // Helper to safely extract Double
        func getDouble(_ key: String) -> Double? {
            if let val = output[key] as? Double { return val }
            if let val = output[key] as? Int { return Double(val) }
            if let val = output[key] as? String {
                // Handle "1/100" string for shutter speed if it comes as string despite #
                if key == "ExposureTime" && val.contains("/") {
                    let parts = val.split(separator: "/")
                    if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den != 0 {
                        return num / den
                    }
                }
                return Double(val)
            }
            return nil
        }
        
        // Helper to safely extract Int
        func getInt(_ key: String) -> Int? {
            if let val = output[key] as? Int { return val }
            if let val = output[key] as? Double { return Int(val) }
            if let val = output[key] as? String { return Int(val) }
            return nil
        }
        
        // Basic Fields
        meta.cameraMake = output["Make"] as? String
        meta.cameraModel = output["Model"] as? String
        meta.lensModel = output["LensModel"] as? String
        meta.software = output["Software"] as? String
        
        // Focal Length
        meta.focalLength = getDouble("FocalLength")
        
        // Aperture
        // Aperture
        meta.aperture = getDouble("FNumber") ?? getDouble("Aperture")
        
        // Shutter Speed
        if let et = getDouble("ExposureTime") ?? getDouble("ShutterSpeed") {
            meta.shutterSpeed = formatShutterSpeed(et)
        }
        
        // ISO
        meta.iso = getInt("ISO")
        
        // Dimensions
        let w = getInt("RawImageWidth") ?? getInt("ExifImageWidth") ?? getInt("ImageWidth")
        let h = getInt("RawImageHeight") ?? getInt("ExifImageHeight") ?? getInt("ImageHeight")
        
        // Orientation
        var orient = 1
        if let o = getInt("Orientation") {
            orient = o
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
        meta.meteringMode = output["MeteringMode"] as? String ?? output["Metering"] as? String
        meta.flash = output["Flash"] as? String
        meta.whiteBalance = output["WhiteBalance"] as? String ?? output["Balance"] as? String
        meta.exposureProgram = output["ExposureProgram"] as? String ?? output["ExposureMode"] as? String ?? output["ShootingMode"] as? String ?? output["CreativeStyle"] as? String
        meta.exposureCompensation = getDouble("ExposureCompensation")
        
        // New Fields
        meta.brightnessValue = getDouble("BrightnessValue")
        meta.exposureBias = getDouble("ExposureBiasValue")
        meta.serialNumber = output["SerialNumber"] as? String ?? output["BodySerialNumber"] as? String
        meta.title = output["Title"] as? String ?? output["ObjectName"] as? String
        meta.caption = output["Caption"] as? String ?? output["Description"] as? String ?? output["ImageDescription"] as? String ?? output["Caption-Abstract"] as? String
        meta.latitude = getDouble("GPSLatitude")
        meta.longitude = getDouble("GPSLongitude")
        meta.altitude = getDouble("GPSAltitude")
        meta.imageDirection = getDouble("GPSImgDirection")
        
        // Rating
        meta.rating = getInt("Rating") ?? getInt("XMP:Rating")
        
        // Label
        if let label = output["Label"] as? String ?? output["XMP:Label"] as? String {
            meta.colorLabel = label
        } else if let urgency = getInt("Urgency") {
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
        
        return meta
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
