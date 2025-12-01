import Foundation

public struct FileItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let isDirectory: Bool
    public let name: String
    public let isAvailable: Bool
    public var isConflict: Bool = false
    public let uuid: UUID? // For Catalog items to access persistent cache
    public var colorLabel: String?
    public let fileCount: Int?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let fileSize: Int64?
    public let orientation: Int?
    
    public init(url: URL, isDirectory: Bool, isAvailable: Bool = true, uuid: UUID? = nil, colorLabel: String? = nil, fileCount: Int? = nil, creationDate: Date? = nil, modificationDate: Date? = nil, fileSize: Int64? = nil, orientation: Int? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.name = url.lastPathComponent
        self.isAvailable = isAvailable
        self.uuid = uuid
        self.colorLabel = colorLabel
        self.fileCount = fileCount
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.orientation = orientation
    }
    
    // Helper for backward compatibility if needed, or just convenience
    
    public static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        return lhs.url == rhs.url && 
               lhs.uuid == rhs.uuid && 
               lhs.fileCount == rhs.fileCount &&
               lhs.modificationDate == rhs.modificationDate &&
               lhs.isAvailable == rhs.isAvailable
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(uuid)
        hasher.combine(fileCount)
        hasher.combine(modificationDate)
        hasher.combine(isAvailable)
    }
}
