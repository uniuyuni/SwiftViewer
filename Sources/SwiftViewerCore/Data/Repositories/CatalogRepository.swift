import Foundation
import CoreData

protocol CatalogRepositoryProtocol {
    func createCatalog(name: String) throws -> Catalog
    func fetchCatalogs() throws -> [Catalog]
    func deleteCatalog(_ catalog: Catalog) throws
}

class CatalogRepository: CatalogRepositoryProtocol {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }
    
    func createCatalog(name: String) throws -> Catalog {
        let catalog = Catalog(context: context)
        catalog.id = UUID()
        catalog.name = name
        catalog.createdDate = Date()
        catalog.modifiedDate = Date()
        
        try context.save()
        return catalog
    }
    
    func fetchCatalogs() throws -> [Catalog] {
        let request: NSFetchRequest<Catalog> = Catalog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Catalog.name, ascending: true)]
        return try context.fetch(request)
    }
    
    func deleteCatalog(_ catalog: Catalog) throws {
        // Delete thumbnails
        // Use explicit fetch to ensure we get all items
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "catalog == %@", catalog)
        
        if let items = try? context.fetch(request) {
            print("CatalogRepository: Deleting thumbnails for \(items.count) items in catalog '\(catalog.name ?? "")'")
            var deletedCount = 0
            for item in items {
                if let uuid = item.id {
                    let url = ThumbnailCacheService.shared.cachePath(for: uuid)
                    if FileManager.default.fileExists(atPath: url.path) {
                        do {
                            try FileManager.default.removeItem(at: url)
                            deletedCount += 1
                        } catch {
                            print("CatalogRepository: Failed to delete thumbnail at \(url.path): \(error)")
                        }
                    }
                }
            }
            print("CatalogRepository: Deleted \(deletedCount) thumbnail files.")
        }
        
        context.delete(catalog)
        try context.save()
    }
}
