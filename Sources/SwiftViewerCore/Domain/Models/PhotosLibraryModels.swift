import Foundation

public struct PhotosLibrary: Identifiable, Hashable, Codable {
    public let id: UUID
    public let name: String
    public let url: URL
    public var bookmarkData: Data?
    
    public init(id: UUID = UUID(), name: String, url: URL, bookmarkData: Data? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.bookmarkData = bookmarkData
    }
}

public struct PhotosAsset: Identifiable, Hashable {
    public let id: String // UUID from ZASSET
    public let filename: String // Original filename
    public let date: Date
    public let directory: String // Directory in 'originals' (e.g. "0/0A...")
    public let path: String // Hashed filename in 'originals'
    public let libraryURL: URL
    public let fileSize: Int64 // File size in bytes
    
    public var originalURL: URL {
        // Construct full path: libraryURL/originals/directory/path
        return libraryURL.appendingPathComponent("originals")
            .appendingPathComponent(directory)
            .appendingPathComponent(path)
    }
    
    public init(id: String, filename: String, date: Date, directory: String, path: String, libraryURL: URL, fileSize: Int64 = 0) {
        self.id = id
        self.filename = filename
        self.date = date
        self.directory = directory
        self.path = path
        self.libraryURL = libraryURL
        self.fileSize = fileSize
    }
}

public struct PhotosDateGroup: Identifiable, Hashable {
    public let id: String // YYYY-MM-DD
    public let date: Date
    public var assets: [PhotosAsset]
    
    public init(date: Date, assets: [PhotosAsset]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.id = formatter.string(from: date)
        self.date = date
        self.assets = assets
    }
}
