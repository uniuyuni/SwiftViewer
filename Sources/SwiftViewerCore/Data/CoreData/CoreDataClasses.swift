import Foundation
import CoreData

@objc(Catalog)
public class Catalog: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var createdDate: Date?
    @NSManaged public var modifiedDate: Date?
    @NSManaged public var color: String?
    @NSManaged public var mediaItems: NSSet?
    @NSManaged public var collections: NSSet?
}

@objc(MediaItem)
public class MediaItem: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var originalPath: String?
    @NSManaged public var fileName: String?
    @NSManaged public var fileSize: Int64
    @NSManaged public var mediaType: String?
    @NSManaged public var captureDate: Date?
    @NSManaged public var importDate: Date?
    @NSManaged public var modifiedDate: Date?
    @NSManaged public var rating: Int16
    @NSManaged public var isFlagged: Bool
    @NSManaged public var colorLabel: String?
    @NSManaged public var orientation: Int16
    @NSManaged public var width: Int32
    @NSManaged public var height: Int32
    @NSManaged public var fileExists: Bool
    @NSManaged public var catalog: Catalog?
    @NSManaged public var collections: NSSet?
    @NSManaged public var exifData: ExifData?
}

@objc(ExifData)
public class ExifData: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var cameraMake: String?
    @NSManaged public var cameraModel: String?
    @NSManaged public var lensModel: String?
    @NSManaged public var focalLength: Double
    @NSManaged public var aperture: Double
    @NSManaged public var shutterSpeed: String?
    @NSManaged public var iso: Int32
    @NSManaged public var dateTimeOriginal: Date?
    @NSManaged public var gpsLatitude: Double
    @NSManaged public var gpsLongitude: Double
    @NSManaged public var copyright: String?
    @NSManaged public var artist: String?
    @NSManaged public var descriptionText: String?
    @NSManaged public var rawProps: Data?
    @NSManaged public var rating: Int16
    @NSManaged public var mediaItem: MediaItem?
}

@objc(Collection)
public class Collection: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var type: String?
    @NSManaged public var filterCriteria: Data?
    @NSManaged public var catalog: Catalog?
    @NSManaged public var mediaItems: NSSet?
}

extension Catalog {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Catalog> {
        return NSFetchRequest<Catalog>(entityName: "Catalog")
    }
}

extension MediaItem {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<MediaItem> {
        return NSFetchRequest<MediaItem>(entityName: "MediaItem")
    }
}
