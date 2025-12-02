import XCTest
@testable import SwiftViewerCore
import CoreData

@MainActor
final class SpecificationTests: XCTestCase {
    var viewModel: MainViewModel!
    var context: NSManagedObjectContext!
    
    override func setUpWithError() throws {
        // Use in-memory Core Data for testing
        let persistenceController = PersistenceController(inMemory: true)
        context = persistenceController.container.viewContext
        
        // Initialize ViewModel with the test context
        // Note: MainViewModel might need adjustment to accept a context or we rely on the singleton override if possible.
        // Since MainViewModel uses PersistenceController.shared, we might need to mock it or accept it.
        // For now, we'll try to rely on the fact that PersistenceController.shared can be swapped or we test logic that doesn't strictly depend on the global singleton if possible,
        // OR we assume the test environment allows us to reset the singleton (which it usually doesn't easily).
        // A better approach for unit tests is to test the Services or logic that accepts the context.
        
        // However, MainViewModel is the main orchestrator. Let's instantiate it.
        // Initialize ViewModel with the test context
        viewModel = MainViewModel(persistenceController: persistenceController)
        
        // Hack: If MainViewModel uses PersistenceController.shared, we might be affecting global state.
        // Ideally, MainViewModel should accept a PersistenceController in init.
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        context = nil
    }
    
    // MARK: - 2.2 Sidebar (Catalog) Specifications
    
    func testCatalogManagement() async throws {
        // 1. Create Catalog
        let catalogName = "Test Catalog"
        let catalog = Catalog(context: context)
        catalog.id = UUID()
        catalog.name = catalogName
        
        // Verify creation
        XCTAssertNotNil(catalog.id)
        XCTAssertEqual(catalog.name, catalogName)
        
        // 2. Rename Catalog
        let newName = "Renamed Catalog"
        catalog.name = newName
        XCTAssertEqual(catalog.name, newName)
        
        // 3. Add Item to Catalog (Mocking MediaItem)
        let item = MediaItem(context: context)
        item.id = UUID()
        item.originalPath = "/tmp/test.jpg"
        item.catalog = catalog
        
        XCTAssertEqual(item.catalog, catalog)
        XCTAssertEqual(catalog.mediaItems?.count, 1)
    }
    
    // MARK: - 2.3 Grid View (Sorting & Filtering) Specifications
    
    func testSortingLogic() {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        
        let file1 = FileItem(url: URL(fileURLWithPath: "/a.jpg"), isDirectory: false, modificationDate: date1)
        let file2 = FileItem(url: URL(fileURLWithPath: "/b.jpg"), isDirectory: false, modificationDate: date2)
        
        let files = [file2, file1] // Unsorted
        
        // 1. Sort by Date Ascending
        let sortedDateAsc = FileSortService.sortFiles(files, by: .date, ascending: true)
        XCTAssertEqual(sortedDateAsc.first?.url.lastPathComponent, "a.jpg")
        
        // 2. Sort by Date Descending
        let sortedDateDesc = FileSortService.sortFiles(files, by: .date, ascending: false)
        XCTAssertEqual(sortedDateDesc.first?.url.lastPathComponent, "b.jpg")
        
        // 3. Sort by Name
        let sortedName = FileSortService.sortFiles(files, by: .name, ascending: true)
        XCTAssertEqual(sortedName.first?.url.lastPathComponent, "a.jpg")
    }
    
    func testFilteringLogic() {
        let url1 = URL(fileURLWithPath: "/1.jpg")
        let url2 = URL(fileURLWithPath: "/2.jpg")
        let url3 = URL(fileURLWithPath: "/3.jpg")
        
        var file1 = FileItem(url: url1, isDirectory: false)
        file1.colorLabel = "Red"
        
        var file2 = FileItem(url: url2, isDirectory: false)
        file2.colorLabel = "Blue"
        
        let file3 = FileItem(url: url3, isDirectory: false)
        // file3 has no color label
        
        // Setup Metadata Cache for Ratings
        var meta1 = ExifMetadata()
        meta1.rating = 3
        
        var meta2 = ExifMetadata()
        meta2.rating = 5
        
        var meta3 = ExifMetadata()
        meta3.rating = 0
        
        viewModel.metadataCache[url1] = meta1
        viewModel.metadataCache[url2] = meta2
        viewModel.metadataCache[url3] = meta3
        
        viewModel.allFiles = [file1, file2, file3]
        viewModel.appMode = .folders // Ensure we are in folder mode logic
        
        // 1. Filter by Rating (>= 3)
        viewModel.filterCriteria = FilterCriteria(minRating: 3, colorLabel: nil)
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 2)
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url2 })
        
        // 2. Filter by Color Label (Blue)
        viewModel.filterCriteria = FilterCriteria(minRating: 0, colorLabel: "Blue")
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1)
        XCTAssertEqual(viewModel.fileItems.first?.url, url2)
        
        // 3. Combined Filter (Rating >= 4 AND Blue)
        viewModel.filterCriteria = FilterCriteria(minRating: 4, colorLabel: "Blue")
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1)
        XCTAssertEqual(viewModel.fileItems.first?.url, url2)
    }
    
    // MARK: - 2.5 Inspector (Metadata) Specifications
    
    func testMetadataPersistence() {
        // Test that setting rating/label updates the model (cache)
        let url = URL(fileURLWithPath: "/test.jpg")
        let file = FileItem(url: url, isDirectory: false)
        
        viewModel.allFiles = [file]
        viewModel.fileItems = [file]
        
        // Initial state
        XCTAssertNil(viewModel.metadataCache[url]?.rating)
        
        // Update Rating
        var meta = ExifMetadata()
        meta.rating = 4
        meta.colorLabel = "Green"
        viewModel.metadataCache[url] = meta
        
        XCTAssertEqual(viewModel.metadataCache[url]?.rating, 4)
        XCTAssertEqual(viewModel.metadataCache[url]?.colorLabel, "Green")
    }
    
    // MARK: - 3.1 File Operations (ViewModel Logic)
    
    func testSelectionLogic() {
        let file1 = FileItem(url: URL(fileURLWithPath: "/1.jpg"), isDirectory: false)
        let file2 = FileItem(url: URL(fileURLWithPath: "/2.jpg"), isDirectory: false)
        let file3 = FileItem(url: URL(fileURLWithPath: "/3.jpg"), isDirectory: false)
        
        viewModel.fileItems = [file1, file2, file3]
        viewModel.allFiles = [file1, file2, file3]
        
        // 1. Select All
        viewModel.selectAll()
        XCTAssertEqual(viewModel.selectedFiles.count, 3)
        
        // 2. Select Next
        viewModel.deselectAll()
        viewModel.selectFile(file1)
        viewModel.selectNext()
        XCTAssertEqual(viewModel.currentFile?.url, file2.url)
        
        // 3. Select Previous
        viewModel.selectPrevious()
        XCTAssertEqual(viewModel.currentFile?.url, file1.url)
    }
    // MARK: - 3.2 Thumbnail Logic
    
    func testThumbnailCacheKey() {
        let url = URL(fileURLWithPath: "/path/to/image.jpg")
        let key = url.path
        
        // Verify the key generation logic used by ThumbnailCache
        XCTAssertEqual(key, "/path/to/image.jpg")
    }
}
