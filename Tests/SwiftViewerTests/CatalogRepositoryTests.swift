import XCTest
import CoreData
@testable import SwiftViewerCore

class CatalogRepositoryTests: XCTestCase {
    var repository: CatalogRepository!
    var context: NSManagedObjectContext!
    
    override func setUp() {
        super.setUp()
        // Use PersistenceController for consistent model loading
        let controller = PersistenceController(inMemory: true)
        context = controller.container.viewContext
        repository = CatalogRepository(context: context)
    }
    
    func testCreateCatalog() throws {
        let catalog = try repository.createCatalog(name: "Test Catalog")
        XCTAssertNotNil(catalog.id)
        XCTAssertEqual(catalog.name, "Test Catalog")
    }
    
    func testFetchCatalogs() throws {
        _ = try repository.createCatalog(name: "Catalog 1")
        _ = try repository.createCatalog(name: "Catalog 2")
        
        let catalogs = try repository.fetchCatalogs()
        XCTAssertEqual(catalogs.count, 2)
    }
    
    func testDeleteCatalog() throws {
        let catalog = try repository.createCatalog(name: "To Delete")
        try repository.deleteCatalog(catalog)
        
        let catalogs = try repository.fetchCatalogs()
        XCTAssertTrue(catalogs.isEmpty)
    }
}
