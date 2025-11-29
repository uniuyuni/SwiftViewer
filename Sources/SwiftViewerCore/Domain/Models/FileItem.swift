import Foundation

struct FileItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let isDirectory: Bool
    let name: String
    let isAvailable: Bool
    var isConflict: Bool = false
    let uuid: UUID? // For Catalog items to access persistent cache
    var colorLabel: String?
    let fileCount: Int?
    let creationDate: Date?
    let modificationDate: Date?
    let fileSize: Int64?
    
    init(url: URL, isDirectory: Bool, isAvailable: Bool = true, uuid: UUID? = nil, colorLabel: String? = nil, fileCount: Int? = nil, creationDate: Date? = nil, modificationDate: Date? = nil, fileSize: Int64? = nil) {
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
    }
    
    // Helper for backward compatibility if needed, or just convenience
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url == rhs.url &&
        lhs.isDirectory == rhs.isDirectory &&
        lhs.name == rhs.name &&
        lhs.isAvailable == rhs.isAvailable &&
        lhs.colorLabel == rhs.colorLabel &&
        lhs.fileCount == rhs.fileCount &&
        lhs.creationDate == rhs.creationDate &&
        lhs.modificationDate == rhs.modificationDate &&
        lhs.fileSize == rhs.fileSize
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
