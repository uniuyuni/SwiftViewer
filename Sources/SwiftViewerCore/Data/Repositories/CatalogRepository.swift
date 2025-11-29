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
        context.delete(catalog)
        try context.save()
    }
}
