import Foundation
import CoreData

public class CatalogService {
    public static let shared = CatalogService()
    
    private let lastOpenedCatalogKey = "LastOpenedCatalogPath"
    public private(set) var currentPackage: CatalogPackage?
    
    private init() {}
    
    public func loadDefaultCatalog() {
        if let path = UserDefaults.standard.string(forKey: lastOpenedCatalogKey),
           let url = URL(string: path) {
            // Check if exists
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                openCatalog(at: url)
                return
            }
        }
        
        // Fallback to default
        let defaultURL = CatalogPackage.defaultLocation
        if !FileManager.default.fileExists(atPath: defaultURL.path) {
            createCatalog(at: defaultURL)
        } else {
            openCatalog(at: defaultURL)
        }
    }
    
    public func createCatalog(at url: URL) {
        let package = CatalogPackage(url: url)
        do {
            try package.ensureDirectoryStructure()
            openCatalog(at: url)
        } catch {
            print("Failed to create catalog at \(url): \(error)")
        }
    }
    
    public func openCatalog(at url: URL) {
        let package = CatalogPackage(url: url)
        currentPackage = package
        
        // Update Persistence
        PersistenceController.shared.switchToCatalog(at: package.databaseURL)
        
        // Update Cache
        ThumbnailCacheService.shared.updateCacheDirectory(to: package.thumbnailsURL)
        
        // Save preference
        UserDefaults.standard.set(url.absoluteString, forKey: lastOpenedCatalogKey)
        
        print("Opened catalog at: \(url.path)")
    }
}
