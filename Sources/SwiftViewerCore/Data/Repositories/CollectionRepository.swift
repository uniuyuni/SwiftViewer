import Foundation
import CoreData
import CoreData

public protocol CollectionRepositoryProtocol {
    func getCollections(in catalog: Catalog) throws -> [Collection]
    func createCollection(name: String, in catalog: Catalog) throws -> Collection
    func renameCollection(_ collection: Collection, to newName: String) throws
    func deleteCollection(_ collection: Collection) throws
    func addMediaItems(_ items: [MediaItem], to collection: Collection) throws
    func removeMediaItems(_ items: [MediaItem], from collection: Collection) throws
    func getAllCatalogs() throws -> [Catalog]
}

public class CollectionRepository: CollectionRepositoryProtocol {
    private let context: NSManagedObjectContext
    
    public init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }
    
    public func getAllCatalogs() throws -> [Catalog] {
        let request = NSFetchRequest<Catalog>(entityName: "Catalog")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request)
    }
    
    public func getCollections(in catalog: Catalog) throws -> [Collection] {
        let request = NSFetchRequest<Collection>(entityName: "Collection")
        request.predicate = NSPredicate(format: "catalog == %@", catalog)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request)
    }
    
    public func createCollection(name: String, in catalog: Catalog) throws -> Collection {
        let collection = Collection(context: context)
        collection.id = UUID()
        collection.name = name
        collection.type = "regular"
        collection.catalog = catalog
        try context.save()
        return collection
    }
    
    public func renameCollection(_ collection: Collection, to newName: String) throws {
        collection.name = newName
        try context.save()
    }
    
    public func deleteCollection(_ collection: Collection) throws {
        context.delete(collection)
        try context.save()
    }
    
    public func addMediaItems(_ items: [MediaItem], to collection: Collection) throws {
        let currentItems = collection.mediaItems?.mutableCopy() as? NSMutableSet ?? NSMutableSet()
        currentItems.addObjects(from: items)
        collection.mediaItems = currentItems
        try context.save()
    }
    
    public func removeMediaItems(_ items: [MediaItem], from collection: Collection) throws {
        let currentItems = collection.mediaItems?.mutableCopy() as? NSMutableSet ?? NSMutableSet()
        items.forEach { currentItems.remove($0) }
        collection.mediaItems = currentItems
        try context.save()
    }
}
