import XCTest
import CoreData
@testable import SwiftViewerCore

class MediaRepositoryTests: XCTestCase {
    var repository: MediaRepository!
    var catalog: Catalog!
    var context: NSManagedObjectContext!
    
    override func setUp() {
        super.setUp()
        let controller = PersistenceController(inMemory: true)
        context = controller.container.viewContext
        repository = MediaRepository(context: context)
        
        let entity = NSEntityDescription.entity(forEntityName: "Catalog", in: context)!
        catalog = Catalog(entity: entity, insertInto: context)
        catalog.id = UUID()
        catalog.name = "Test Catalog"
        try? context.save()
    }
    
    func testAddMediaItem() async throws {
        // Create a temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_image.jpg")
        try "fake image data".write(to: tempURL, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let item = try await repository.addMediaItem(from: tempURL, to: catalog)
        XCTAssertEqual(item.fileName, "test_image.jpg")
        XCTAssertEqual(item.catalog, catalog)
    }
}
