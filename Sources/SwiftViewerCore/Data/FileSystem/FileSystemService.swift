import Foundation

actor FileSystemService {
    static let shared = FileSystemService()
    
    nonisolated func getColorLabel(from url: URL) -> String? {
        // Try labelNumber first (standard color tags)
        if let values = try? url.resourceValues(forKeys: [.labelNumberKey, .tagNamesKey]),
           let labelNumber = values.labelNumber {
            switch labelNumber {
            case 1: return "Gray"
            case 2: return "Green"
            case 3: return "Purple"
            case 4: return "Blue"
            case 5: return "Yellow"
            case 6: return "Red"
            case 7: return "Orange"
            default: break
            }
        }
        
        // Fallback: Check tagNames (Finder Tags)
        // This handles cases where labelNumber might be missing but tags exist
        if let values = try? url.resourceValues(forKeys: [.tagNamesKey]),
           let tags = values.tagNames {
            // Check for standard color names in tags
            let colors = ["Gray", "Green", "Purple", "Blue", "Yellow", "Red", "Orange"]
            for tag in tags {
                if let color = colors.first(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                    // Return capitalized color name
                    return color
                }
            }
        }
        
        return nil
    }

    nonisolated func getContentsOfDirectory(at url: URL, calculateCounts: Bool = false) -> [FileItem] {
        do {
            let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .labelNumberKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey]
            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
            
            let fileURLs = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: resourceKeys, options: options)
            
            return fileURLs.compactMap { url in
                // Check for cancellation periodically
                if Task.isCancelled {
                    // If cancelled, return nil to stop processing this item and filter it out.
                    // The calling context should handle the cancellation (e.g., by catching a CancellationError if this were a throwing function).
                    // For a non-throwing function returning an array, we just stop processing further items.
                    return nil
                }

                let resourceValues = try? url.resourceValues(forKeys: Set(resourceKeys))
                let isDirectory = resourceValues?.isDirectory ?? false
                let isPackage = resourceValues?.isPackage ?? false
                let label = getColorLabel(from: url)
                let creationDate = resourceValues?.creationDate
                let modificationDate = resourceValues?.contentModificationDate
                let fileSize = Int64(resourceValues?.fileSize ?? 0)
                
                // Calculate file count for directories (non-recursive for performance, or recursive if needed)
                // Only calculate if requested
                var count: Int? = nil
                if calculateCounts && isDirectory && !isPackage {
                    count = getFileCount(at: url)
                }
                
                return FileItem(url: url, isDirectory: isDirectory && !isPackage, isAvailable: true, colorLabel: label, fileCount: count, creationDate: creationDate, modificationDate: modificationDate, fileSize: fileSize)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            print("Error listing directory: \(error)")
            return []
        }
    }
    
    nonisolated func getRootFolders(calculateCounts: Bool = true) -> [FileItem] {
        let fileManager = FileManager.default
        
        // 1. Get Mounted Volumes
        let volumes = getMountedVolumes(calculateCounts: calculateCounts)
        
        // 2. Get Standard Folders
        let paths = [
            fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ].compactMap { $0 }
        
        let standardFolders = paths.map { url in
            let count = calculateCounts ? getFileCount(at: url) : nil
            return FileItem(url: url, isDirectory: true, colorLabel: getColorLabel(from: url), fileCount: count)
        }
        
        // Combine: Volumes first, then Standard Folders
        return volumes + standardFolders
    }
    
    nonisolated func getMountedVolumes(calculateCounts: Bool = true) -> [FileItem] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey]
        let paths = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes])
        
        guard let urls = paths else { return [] }
        
        return urls.compactMap { url in
            // Filter out system volumes if needed, or just show all
            // Typically we want /Volumes/* or "/"
            // But mountedVolumeURLs returns "/" as well.
            
            // Let's filter for Removable or Root
            // Or just return all visible ones.
            // Common practice: Show "/" as "Macintosh HD" (or actual name) and external drives.
            
            // Filter out things that are not file URLs (shouldn't happen)
            guard url.isFileURL else { return nil }
            
            // Optional: Filter out Time Machine backups or specific system volumes if problematic
            
            let count = calculateCounts ? getFileCount(at: url) : nil
            return FileItem(url: url, isDirectory: true, colorLabel: nil, fileCount: count)
        }
    }
    
    nonisolated func getFiles(in url: URL, recursive: Bool = false, fetchMetadata: Bool = true) throws -> [FileItem] {
        var resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        if fetchMetadata {
            resourceKeys.append(.labelNumberKey)
        }
        
        // Fix for duplicates: Skip package descendants
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        
        // Allowed extensions for filtering
        let allowedExtensions = FileConstants.allAllowedExtensions
        
        if recursive {
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: resourceKeys, options: options) else {
                return []
            }
            
            var files: [FileItem] = []
            
            for case let fileURL as URL in enumerator {
                // Check for cancellation periodically
                if Task.isCancelled { break }
                
                // Optimization: If not fetching metadata, try to use cached resource values from enumerator
                let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
                let isDirectory = resourceValues?.isDirectory ?? false
                let isPackage = resourceValues?.isPackage ?? false
                
                if !isDirectory || isPackage {
                    // Filter by extension EARLY
                    let ext = fileURL.pathExtension.lowercased()
                    if allowedExtensions.contains(ext) {
                        // Only fetch label if requested
                        let label = fetchMetadata ? getColorLabel(from: fileURL) : nil
                        let creationDate = resourceValues?.creationDate
                        let modificationDate = resourceValues?.contentModificationDate
                        let fileSize = Int64(resourceValues?.fileSize ?? 0)
                        files.append(FileItem(url: fileURL, isDirectory: false, colorLabel: label, creationDate: creationDate, modificationDate: modificationDate, fileSize: fileSize))
                    }
                }
            }
            return files
        } else {
            // Non-recursive: Use contentsOfDirectory for speed
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: resourceKeys, options: .skipsHiddenFiles)
            return contents.compactMap { fileURL -> FileItem? in
                let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
                let isDirectory = resourceValues?.isDirectory ?? false
                let isPackage = resourceValues?.isPackage ?? false
                
                if !isDirectory || isPackage {
                    let ext = fileURL.pathExtension.lowercased()
                    if allowedExtensions.contains(ext) {
                        let label = fetchMetadata ? getColorLabel(from: fileURL) : nil
                        let creationDate = resourceValues?.creationDate
                        let modificationDate = resourceValues?.contentModificationDate
                        let fileSize = Int64(resourceValues?.fileSize ?? 0)
                        return FileItem(url: fileURL, isDirectory: false, colorLabel: label, creationDate: creationDate, modificationDate: modificationDate, fileSize: fileSize)
                    }
                }
                return nil
            }
        }
    }
    
    nonisolated func getFileCount(at url: URL) -> Int {
        // Non-recursive count of allowed files (images/videos)
        // User requested to NOT count subfolders to improve performance.
        
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: resourceKeys, options: options) else {
            return 0
        }
        
        var count = 0
        for fileURL in contents {
            let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
            let isDirectory = resourceValues?.isDirectory ?? false
            let isPackage = resourceValues?.isPackage ?? false
            
            if !isDirectory || isPackage {
                let ext = fileURL.pathExtension.lowercased()
                if FileConstants.allAllowedExtensions.contains(ext) {
                    count += 1
                }
            }
        }
        return count
    }
    

}
