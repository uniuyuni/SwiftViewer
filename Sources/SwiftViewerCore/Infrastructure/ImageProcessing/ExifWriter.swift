import Foundation
import CoreData

class ExifWriter {
    static let shared = ExifWriter()
    
    func updateExif(for mediaItem: MediaItem, context: NSManagedObjectContext, updates: (ExifData) -> Void) throws {
        guard let exif = mediaItem.exifData else {
            // Create if missing
            let newExif = ExifData(context: context)
            newExif.id = UUID()
            mediaItem.exifData = newExif
            updates(newExif)
            try context.save()
            return
        }
        
        updates(exif)
        try context.save()
        
        // TODO: Write back to file or sidecar
    }
}
