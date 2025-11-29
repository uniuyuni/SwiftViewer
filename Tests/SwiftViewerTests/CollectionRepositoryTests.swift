import XCTest
import CoreData
@testable import SwiftViewerCore

class CollectionRepositoryTests: XCTestCase {
    var repository: CollectionRepository!
    var catalog: Catalog!
    var context: NSManagedObjectContext!
    
    override func setUp() {
        super.setUp()
        let controller = PersistenceController(inMemory: true)
        context = controller.container.viewContext
        repository = CollectionRepository(context: context)
        
        // Create a dummy catalog
        let entity = NSEntityDescription.entity(forEntityName: "Catalog", in: context)!
        catalog = Catalog(entity: entity, insertInto: context)
        catalog.id = UUID()
        catalog.name = "Test Catalog"
        try? context.save()
    }
    
    func testCreateCollection() throws {
        let collection = try repository.createCollection(name: "My Collection", in: catalog)
        XCTAssertEqual(collection.name, "My Collection")
        XCTAssertEqual(collection.catalog, catalog)
    }
    
    func testGetCollections() throws {
        _ = try repository.createCollection(name: "C1", in: catalog)
        _ = try repository.createCollection(name: "C2", in: catalog)
        
        let collections = try repository.getCollections(in: catalog)
        XCTAssertEqual(collections.count, 2)
    }
}
