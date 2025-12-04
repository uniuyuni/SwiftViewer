import Foundation

public struct CatalogPackage: Codable, Equatable {
    public let url: URL
    
    public var databaseURL: URL {
        url.appendingPathComponent("Catalog.sqlite")
    }
    
    public var thumbnailsURL: URL {
        url.appendingPathComponent("Thumbnails")
    }
    
    public var name: String {
        url.deletingPathExtension().lastPathComponent
    }
    
    public init(url: URL) {
        self.url = url
    }
    
    public func ensureDirectoryStructure() throws {
        let fileManager = FileManager.default
        
        // Create package directory
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        
        // Create thumbnails directory
        if !fileManager.fileExists(atPath: thumbnailsURL.path) {
            try fileManager.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
        }
    }
    
    public static var defaultLocation: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        return pictures.appendingPathComponent("SwiftViewer Catalog.svdata")
    }
}
