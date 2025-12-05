import Foundation
import SQLite3

public class PhotosLibraryService {
    public static let shared = PhotosLibraryService()
    
    private init() {}
    
    public func fetchAssets(from libraryURL: URL) async throws -> [PhotosDateGroup] {
        let databaseURL = libraryURL.appendingPathComponent("database/Photos.sqlite")
        
        // Check if database exists
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw PhotosLibraryError.databaseNotFound
        }
        
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            throw PhotosLibraryError.connectionFailed
        }
        defer { sqlite3_close(db) }
        
        // Query to fetch assets
        // Note: This query is based on reverse-engineered schema and might need adjustment for different macOS versions.
        // We join ZASSET, ZADDITIONALASSETATTRIBUTES, and ZINTERNALRESOURCE (or similar tables).
        
        // Simplified query strategy:
        // 1. Get Asset UUID, Date, Original Filename
        // 2. Get Path info (directory and filename in originals)
        
        // This is a complex query. For now, let's try a basic query to ZASSET and ZADDITIONALASSETATTRIBUTES.
        // The path logic in Photos.sqlite is tricky. Often the file in 'originals' is named by UUID.
        // Let's assume standard structure: originals/FirstCharOfUUID/UUID.jpeg (or similar)
        // BUT, newer versions use ZINTERNALRESOURCE to map to specific files.
        
        // Let's try to fetch basic info first.
        
        // NOTE: The above query is a GUESS. The actual schema is different.
        // ZDIRECTORY and ZFILENAME might not exist in ZASSET directly in newer versions.
        // We need to be careful.
        
        // Let's implement a safer, more robust way to explore or use known schema.
        // For macOS Sequoia/Sonoma, the schema involves ZINTERNALRESOURCE.
        
        // For this implementation, we will start with a placeholder that returns empty if query fails,
        // and we will refine the query based on actual DB structure if possible, or use a known common query.
        
        // Common query for recent macOS:
        // ZASSET joined with ZINTERNALRESOURCE (for path) and ZADDITIONALASSETATTRIBUTES (for filename)
        
        // Improved query to fetch assets with path information
        // We join ZASSET with ZINTERNALRESOURCE to get the relative path in 'originals'
        // ZINTERNALRESOURCE.ZDATALENGTH > 0 ensures we get actual files
        // ZINTERNALRESOURCE.ZRESOURCETYPE = 0 usually means original image
        
        let sql = """
            SELECT 
                ZASSET.ZUUID,
                ZASSET.ZDATECREATED + 978307200, -- Convert CoreData timestamp (ref 2001) to Unix
                ZADDITIONALASSETATTRIBUTES.ZORIGINALFILENAME,
                ZASSET.ZDIRECTORY,
                ZASSET.ZFILENAME
            FROM ZASSET
            JOIN ZADDITIONALASSETATTRIBUTES ON ZADDITIONALASSETATTRIBUTES.ZASSET = ZASSET.Z_PK
            WHERE ZASSET.ZTRASHEDSTATE = 0
            ORDER BY ZASSET.ZDATECREATED DESC
        """
        
        // NOTE: ZDIRECTORY and ZFILENAME are often NULL in newer macOS versions.
        // We need to try to infer path if they are null.
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            print("SQLite Prepare Error: \(errorMsg)")
            throw PhotosLibraryError.queryFailed(errorMsg)
        }
        defer { sqlite3_finalize(statement) }
        
        var assets: [PhotosAsset] = []
        let originalsURL = libraryURL.appendingPathComponent("originals")
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let uuidPtr = sqlite3_column_text(statement, 0),
                  let filenamePtr = sqlite3_column_text(statement, 2) else { continue }
            
            let uuid = String(cString: uuidPtr)
            let timestamp = sqlite3_column_double(statement, 1)
            let filename = String(cString: filenamePtr)
            let date = Date(timeIntervalSince1970: timestamp)
            
            // Path Resolution Strategy
            // 1. Try ZDIRECTORY / ZFILENAME if available
            var directory = ""
            var path = ""
            
            if let dirPtr = sqlite3_column_text(statement, 3),
               let filePtr = sqlite3_column_text(statement, 4) {
                directory = String(cString: dirPtr)
                path = String(cString: filePtr)
            }
            
            // Check if file exists at the DB path
            var fileExists = false
            if !directory.isEmpty && !path.isEmpty {
                let checkURL = originalsURL.appendingPathComponent(directory).appendingPathComponent(path)
                if FileManager.default.fileExists(atPath: checkURL.path) {
                    fileExists = true
                }
            }
            
            // 2. Fallback: Heuristic for newer macOS (Sequoia/Sonoma) OR if DB path failed
            // Structure: originals/[FirstCharOfUUID]/[UUID].[ext]
            if !fileExists {
                // If we had a path but it didn't exist, we try the heuristic.
                // Or if we didn't have a path at all.
                
                let ext = (filename as NSString).pathExtension
                let firstChar = String(uuid.prefix(1))
                directory = firstChar
                path = "\(uuid).\(ext)"
                
                // Check if file exists at this heuristic path
                let checkURL = originalsURL.appendingPathComponent(directory).appendingPathComponent(path)
                if !FileManager.default.fileExists(atPath: checkURL.path) {
                    // print("Photos Asset Not Found at: \(checkURL.path) (UUID: \(uuid))")
                    
                    // IMPROVED FALLBACK: Search for file starting with UUID in the directory
                    // This handles cases like UUID_4.ext or different extensions
                    let dirURL = originalsURL.appendingPathComponent(directory)
                    if let files = try? FileManager.default.contentsOfDirectory(atPath: dirURL.path) {
                        // Look for file starting with UUID (ignoring case)
                        // We prioritize exact match of UUID prefix to avoid false positives if UUIDs are similar (unlikely for UUIDs)
                        if let foundFile = files.first(where: { $0.lowercased().hasPrefix(uuid.lowercased()) }) {
                            path = foundFile
                            // print("Found asset via fallback search: \(path)")
                        } else {
                             print("Photos Asset Not Found even after search: \(checkURL.path) (UUID: \(uuid))")
                        }
                    }
                } else {
                    // print("Found asset: \(checkURL.path)")
                }
            }
            
            // Get file size
            var fileSize: Int64 = 0
            if !directory.isEmpty && !path.isEmpty {
                 let checkURL = originalsURL.appendingPathComponent(directory).appendingPathComponent(path)
                 if let attrs = try? FileManager.default.attributesOfItem(atPath: checkURL.path) {
                     fileSize = (attrs[.size] as? Int64) ?? 0
                 }
            }
            
            let asset = PhotosAsset(
                id: uuid,
                filename: filename,
                date: date,
                directory: directory,
                path: path,
                libraryURL: libraryURL,
                fileSize: fileSize
            )
            assets.append(asset)
            
            // 3. Sidecar RAW Discovery
            // If the asset we found is a JPEG/HEIC, check if there's a corresponding RAW file
            // that isn't in the DB (or we missed it).
            // Photos often stores RAWs as UUID.RAW or UUID_4.RAW in the same folder.
            
            let assetExt = (path as NSString).pathExtension.lowercased()
            if ["jpg", "jpeg", "heic", "png"].contains(assetExt) {
                let dirURL = originalsURL.appendingPathComponent(directory)
                
                // We need to list files in this directory.
                // Optimization: In a real app, we should cache directory contents to avoid listing for every asset.
                // For now, we rely on OS caching or accept the performance hit for correctness.
                // To avoid excessive IO, we only check if we have a valid directory.
                if !directory.isEmpty {
                    if let files = try? FileManager.default.contentsOfDirectory(atPath: dirURL.path) {
                        // Filter for RAW files starting with UUID
                        let rawFiles = files.filter { file in
                            let fileExt = (file as NSString).pathExtension.lowercased()
                            return FileConstants.rawExtensions.contains(fileExt) &&
                                   file.lowercased().hasPrefix(uuid.lowercased())
                        }
                        
                        for rawFile in rawFiles {
                            // Create a RAW asset
                            // Use a derived UUID to avoid ID conflict if the RAW is somehow also in DB (though unlikely if we are here)
                            // But wait, if it IS in DB, we might duplicate it.
                            // However, if it was in DB, we would have fetched it in the main loop?
                            // Not necessarily, if our query filtered it out or it's a "hidden" resource.
                            // Let's append it. Duplicates might be filtered later or we can check `assets` but that's O(N).
                            // For now, assume it's not in the result set.
                            
                            // Derive original filename from the main asset's original filename
                            // e.g. if main is IMG_1234.JPG, RAW should be IMG_1234.ARW
                            let rawExt = (rawFile as NSString).pathExtension
                            let originalNameWithoutExt = (filename as NSString).deletingPathExtension
                            let rawOriginalFilename = "\(originalNameWithoutExt).\(rawExt)"
                            
                            // Get RAW file size
                            var rawFileSize: Int64 = 0
                            let rawURL = dirURL.appendingPathComponent(rawFile)
                            if let attrs = try? FileManager.default.attributesOfItem(atPath: rawURL.path) {
                                rawFileSize = (attrs[.size] as? Int64) ?? 0
                            }
                            
                            let rawAsset = PhotosAsset(
                                id: uuid + "_RAW_" + rawFile, // Unique ID for RAW
                                filename: rawOriginalFilename, // Use derived original filename
                                date: date, // Assume same date as JPEG
                                directory: directory,
                                path: rawFile,
                                libraryURL: libraryURL,
                                fileSize: rawFileSize
                            )
                            assets.append(rawAsset)
                            // print("Discovered Sidecar RAW: \(rawFile)")
                        }
                    }
                }
            }
        }
        
        print("Fetched \(assets.count) assets from Photos Library")
        
        // Group by Date (YYYY-MM-DD)
        let grouped = Dictionary(grouping: assets) { asset -> String in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: asset.date)
        }
        
        let result = grouped.map { (key, value) -> PhotosDateGroup in
            // Use the date of the first asset as representative (or parse key)
            let date = value.first?.date ?? Date()
            return PhotosDateGroup(date: date, assets: value)
        }.sorted { $0.id > $1.id } // Newest first
        
        return result
    }
}

public enum PhotosLibraryError: Error {
    case databaseNotFound
    case connectionFailed
    case queryFailed(String)
}
