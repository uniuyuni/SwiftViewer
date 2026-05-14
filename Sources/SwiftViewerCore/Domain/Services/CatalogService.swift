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
    
    /// カタログを安全に開く。DBが壊れている/互換性が無い等でCoreDataストアが読み込めない場合はthrowし、
    /// currentPackage や lastOpenedCatalogKey などの状態を更新しない。
    @MainActor
    public func openCatalogSafely(at url: URL) async throws {
        let package = CatalogPackage(url: url)
        
        // 先にストアが読めるかを確認（成功した場合のみ状態を更新）
        try await PersistenceController.shared.switchToCatalogAsync(at: package.databaseURL)
        
        currentPackage = package
        ThumbnailCacheService.shared.updateCacheDirectory(to: package.thumbnailsURL)
        UserDefaults.standard.set(url.absoluteString, forKey: lastOpenedCatalogKey)
        
        print("Opened catalog at: \(url.path)")
    }
}
