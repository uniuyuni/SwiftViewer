import Foundation

public struct FileItem: Identifiable, Hashable, Sendable {
    public var id: String {
        if let uuid = uuid {
            return uuid.uuidString
        }
        return url.path
    }
    public let url: URL
    public let isDirectory: Bool
    public let name: String
    public let isAvailable: Bool
    public var isConflict: Bool = false
    public var uuid: UUID? // For Catalog items to access persistent cache
    public var colorLabel: String?
    public var isFavorite: Bool?
    public var flagStatus: Int16?  // -1: Reject, 0: None, 1: Pick
    public let fileCount: Int?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let fileSize: Int64?
    public let orientation: Int?
    public var rating: Int? // 0-5
    
    public init(url: URL, isDirectory: Bool, isAvailable: Bool = true, uuid: UUID? = nil, colorLabel: String? = nil, isFavorite: Bool? = nil, flagStatus: Int16? = nil, fileCount: Int? = nil, creationDate: Date? = nil, modificationDate: Date? = nil, fileSize: Int64? = nil, orientation: Int? = nil, rating: Int? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.name = url.lastPathComponent
        self.isAvailable = isAvailable
        self.uuid = uuid
        self.colorLabel = colorLabel
        self.isFavorite = isFavorite
        self.flagStatus = flagStatus
        self.fileCount = fileCount
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.orientation = orientation
        self.rating = rating
    }
    
    // Helper for backward compatibility if needed, or just convenience
    
    public static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        return lhs.id == rhs.id &&
               lhs.colorLabel == rhs.colorLabel &&
               lhs.isFavorite == rhs.isFavorite &&
               lhs.flagStatus == rhs.flagStatus &&
               lhs.modificationDate == rhs.modificationDate &&
               lhs.isAvailable == rhs.isAvailable &&
               lhs.fileCount == rhs.fileCount &&
               lhs.rating == rhs.rating &&
               lhs.fileSize == rhs.fileSize &&
               lhs.creationDate == rhs.creationDate &&
               lhs.orientation == rhs.orientation
    }
    
    public func hash(into hasher: inout Hasher) {
        // Hash only identity for performance in Sets/Dictionaries where stability matters
        // But for SwiftUI List, it uses Identifiable.id
        hasher.combine(id)
    }
}
