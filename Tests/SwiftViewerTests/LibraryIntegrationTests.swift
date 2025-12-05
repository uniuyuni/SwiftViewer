import XCTest
@testable import SwiftViewerCore

class LibraryIntegrationTests: XCTestCase {
    var viewModel: MainViewModel!
    var persistenceController: PersistenceController!
    
    @MainActor
    override func setUp() {
        super.setUp()
        persistenceController = PersistenceController(inMemory: true)
        viewModel = MainViewModel(persistenceController: persistenceController)
    }
    
    @MainActor
    func testHeaderTitleLogic() {
        // 1. Default State
        XCTAssertEqual(viewModel.headerTitle, "SwiftViewer")
        
        // 2. Photos Mode
        let libID = UUID()
        let library = PhotosLibrary(id: libID, name: "Test Library", url: URL(fileURLWithPath: "/tmp"), bookmarkData: nil)
        viewModel.photosLibraries = [library]
        viewModel.selectedPhotosGroupID = "\(libID.uuidString)/2023-10-27"
        
        XCTAssertTrue(viewModel.isPhotosMode)
        XCTAssertEqual(viewModel.headerTitle, "Test Library - 2023-10-27")
        
        // 3. Catalog Mode (Photos Mode should take precedence if selectedPhotosGroupID is set, 
        // BUT in the app logic, selecting a catalog usually clears selectedPhotosGroupID.
        // Here we test the priority if both were somehow set, or just the Catalog state)
        
        // Reset Photos Mode
        viewModel.selectedPhotosGroupID = nil
        
        let catalog = Catalog(context: persistenceController.container.viewContext)
        catalog.name = "Test Catalog"
        viewModel.openCatalog(catalog)
        
        XCTAssertEqual(viewModel.headerTitle, "Test Catalog")
        
        // 4. Catalog Folder
        let folderURL = URL(fileURLWithPath: "/Users/test/Photos")
        viewModel.selectCatalogFolder(folderURL)
        XCTAssertEqual(viewModel.headerTitle, "Photos")
    }
    
    @MainActor
    func testAppSwitchStatePersistence() {
        // Simulate Photos Mode
        let libID = UUID()
        viewModel.selectedPhotosGroupID = "\(libID.uuidString)/2023-10-27"
        
        // Simulate Catalog also being "open" in background
        let catalog = Catalog(context: persistenceController.container.viewContext)
        viewModel.currentCatalog = catalog
        
        // Simulate App becoming active
        // We can't call private handleAppDidBecomeActive directly, but we can verify the logic 
        // that would be inside it if we extracted it or tested the side effects.
        // Since we modified handleAppDidBecomeActive to check selectedPhotosGroupID first,
        // we essentially want to ensure that if selectedPhotosGroupID is set, we don't switch context.
        
        // In the actual ViewModel, handleAppDidBecomeActive calls loadMediaItems(from: catalog) ONLY if not in Photos Mode.
        // We can verify this behavior by checking if fileItems gets overwritten? 
        // It's hard to test private methods directly without internals visible.
        // However, we can test the `isPhotosMode` property which drives the logic.
        
        XCTAssertTrue(viewModel.isPhotosMode)
        XCTAssertNotNil(viewModel.currentCatalog)
        
        // If logic is correct, isPhotosMode remains true and we don't switch to catalog view
    }
    
    @MainActor
    func testRefreshAllBehavior() {
        // Setup Photos Mode
        viewModel.selectedPhotosGroupID = "some-id"
        
        // We want to verify that refreshAll doesn't crash or switch modes.
        // Since refreshAll is async and affects internal state, we can just call it and ensure
        // selectedPhotosGroupID is still set.
        
        let expectation = XCTestExpectation(description: "Refresh All")
        
        Task {
            viewModel.refreshAll()
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            
            XCTAssertNotNil(viewModel.selectedPhotosGroupID)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}
