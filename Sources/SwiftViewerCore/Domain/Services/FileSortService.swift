import Foundation

struct FileSortService {
    static func sortFiles(_ files: [FileItem], by option: MainViewModel.SortOption, ascending: Bool, metadataCache: [URL: ExifMetadata] = [:]) -> [FileItem] {
        let sorted = files.sorted { file1, file2 in
            let result: Bool
            switch option {
            case .name:
                // Special handling for same filename but different extension
                let name1 = file1.url.deletingPathExtension().lastPathComponent
                let name2 = file2.url.deletingPathExtension().lastPathComponent
                
                if name1 == name2 {
                    // Same name, check extensions
                    let ext1 = file1.url.pathExtension.lowercased()
                    let ext2 = file2.url.pathExtension.lowercased()
                    
                    // Priority: RGB (jpg, png, etc) < RAW
                    let isRaw1 = isRaw(ext1)
                    let isRaw2 = isRaw(ext2)
                    
                    if isRaw1 != isRaw2 {
                        // If one is RAW and other is not, non-RAW comes first
                        return !isRaw1 // true if file1 is NOT raw (so it comes first)
                    } else {
                        // Both RAW or both non-RAW, sort alphabetically by extension
                        return ext1 < ext2
                    }
                }
                
                result = file1.name.localizedStandardCompare(file2.name) == .orderedAscending
                
            case .date:
                // Priority: Exif Date > Modification Date > Creation Date
                let date1 = metadataCache[file1.url]?.dateTimeOriginal ?? file1.modificationDate ?? file1.creationDate ?? Date.distantPast
                let date2 = metadataCache[file2.url]?.dateTimeOriginal ?? file2.modificationDate ?? file2.creationDate ?? Date.distantPast
                
                if date1 != date2 {
                    result = date1 < date2
                } else {
                    result = file1.name.localizedStandardCompare(file2.name) == .orderedAscending
                }
                
            case .size:
                 let size1 = file1.fileSize ?? 0
                 let size2 = file2.fileSize ?? 0
                 if size1 != size2 {
                     result = size1 < size2
                 } else {
                     result = file1.name.localizedStandardCompare(file2.name) == .orderedAscending
                 }
            }
            
            return ascending ? result : !result
        }
        
        if option == .date && !sorted.isEmpty {
            let first = sorted.first!
            let firstDate = metadataCache[first.url]?.dateTimeOriginal ?? first.modificationDate ?? first.creationDate
            Logger.shared.log("FileSortService: Sorted \(sorted.count) files by date. First: \(first.name) (\(String(describing: firstDate)))")
        }
        
        return sorted
    }
    
    private static func isRaw(_ ext: String) -> Bool {
        // Simple check: if it's in allowedImageExtensions but NOT in common RGB formats
        let commonRGB = ["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"]
        return !commonRGB.contains(ext) && FileConstants.allowedImageExtensions.contains(ext)
    }
}
