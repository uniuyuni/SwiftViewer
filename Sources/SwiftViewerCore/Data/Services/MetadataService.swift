import AppKit
import CoreData
import Foundation
import ImageIO

class MetadataService {
    static let shared = MetadataService()

    private init() {}

    // MARK: - Public API
    
    func isExifToolAvailable() -> Bool {
        return getExifToolPath() != nil
    }

    func updateRating(for file: FileItem, rating: Int, in context: NSManagedObjectContext?)
        async throws
    {
        let isRAW = FileConstants.rawExtensions.contains(file.url.pathExtension.lowercased())
        // let isCatalogItem = context != nil // Unused

        // Rule: RAW -> Disabled completely (User Request Round 50)
        if isRAW {
            throw MetadataError.editingNotAllowed("Cannot edit RAW files.")
        }

        // 1. Update Catalog (Core Data)
        if let context = context {
            await updateCatalogRating(file: file, rating: rating, context: context)
        }

        // 2. Update File (RGB only)
        if !isRAW {
            try await updateFileRating(file: file, rating: rating)
        }
    }

    func updateColorLabel(for file: FileItem, label: String?, in context: NSManagedObjectContext?)
        async throws
    {
        let isRAW = FileConstants.rawExtensions.contains(file.url.pathExtension.lowercased())
        // let isCatalogItem = context != nil // Unused

        if isRAW {
            throw MetadataError.editingNotAllowed("Cannot edit RAW files.")
        }

        // 1. Update Catalog
        if let context = context {
            await updateCatalogLabel(file: file, label: label, context: context)
        }

        // 2. Update File (Finder Tags) - Allowed for both RGB and RAW (since it's FS metadata, not embedded)
        // Wait, user said "RAW image writes to catalog only".
        // Does this apply to Finder Tags (Color Label) too?
        // Usually "Color Label" in apps syncs with Finder Tags.
        // If user says "write to file", they might mean embedded metadata.
        // But Finder Tags are external.
        // Let's assume strict rule: RAW -> Catalog Only.
        // 2. Update File (Finder Tags) - Allowed for both RGB and RAW (since it's FS metadata, not embedded)
        // But user requested NO editing for RAW files at all to avoid confusion.
        if !isRAW {
            try updateFileLabel(file: file, label: label)
        }
    }

    // MARK: - Internal Logic

    private func updateCatalogRating(file: FileItem, rating: Int, context: NSManagedObjectContext)
        async
    {
        await context.perform {
            let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
            request.predicate = NSPredicate(format: "originalPath == %@", file.url.path)
            if let item = try? context.fetch(request).first {
                item.rating = Int16(rating)

                // Update ExifData relationship if needed
                if item.exifData == nil {
                    let exif = ExifData(context: context)
                    item.exifData = exif
                }
                item.exifData?.rating = Int16(rating)

                try? context.save()
            }
        }
    }

    private func updateCatalogLabel(file: FileItem, label: String?, context: NSManagedObjectContext)
        async
    {
        await context.perform {
            let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
            request.predicate = NSPredicate(format: "originalPath == %@", file.url.path)
            if let item = try? context.fetch(request).first {
                item.colorLabel = label
                try? context.save()
            }
        }
    }

    private func updateFileRating(file: FileItem, rating: Int) async throws {
        guard let exifToolPath = getExifToolPath() else {
            print("ExifTool not found. Cannot write metadata to file.")
            return
        }
        
        let url = file.url
        
        // Command: exiftool -Rating=N -overwrite_original_in_place [file]
        // Note: -overwrite_original_in_place preserves file creation date and attributes (like Finder tags/Label)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exifToolPath)
        process.arguments = ["-Rating=\(rating)", "-overwrite_original_in_place", url.path]
        process.environment = ProcessInfo.processInfo.environment
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if !errorData.isEmpty {
            if let errorString = String(data: errorData, encoding: .utf8) {
                print("ExifTool stderr: \(errorString)")
            }
        }
        
        if process.terminationStatus == 0 {
            print("Successfully updated rating for \(url.lastPathComponent)")
            ExifReader.shared.invalidateCache(for: url)
        } else {
            print("ExifTool failed with status \(process.terminationStatus)")
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

    private func updateFileLabel(file: FileItem, label: String?) throws {
        // Map Label String to Finder Tag Color
        // Red, Orange, Yellow, Green, Blue, Purple, Gray
        let url = file.url
        var resourceValues = URLResourceValues()

        if let label = label {
            // Map string to Label Number (1-7)
            let labelNumber: Int?
            switch label {
            case "Gray": labelNumber = 1
            case "Green": labelNumber = 2
            case "Purple": labelNumber = 3
            case "Blue": labelNumber = 4
            case "Yellow": labelNumber = 5
            case "Red": labelNumber = 6
            case "Orange": labelNumber = 7
            default: labelNumber = nil
            }
            resourceValues.labelNumber = labelNumber
        } else {
            resourceValues.labelNumber = nil
        }

        var fileURL = url
        try fileURL.setResourceValues(resourceValues)
        
        // Also write XMP Label using ExifTool if available
        if let exifToolPath = getExifToolPath() {
            let labelArg = label != nil ? "-XMP:Label=\(label!)" : "-XMP:Label="
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: exifToolPath)
            process.arguments = [labelArg, "-overwrite_original_in_place", url.path]
            
            // Run asynchronously to avoid blocking
            Task.detached {
                try? process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    ExifReader.shared.invalidateCache(for: url)
                }
            }
        }
    }

    enum MetadataError: Error {
        case editingNotAllowed(String)
    }
}
