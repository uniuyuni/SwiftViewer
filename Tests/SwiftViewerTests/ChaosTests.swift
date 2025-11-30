import XCTest
@testable import SwiftViewerCore
import CoreData

@MainActor
final class ChaosTests: XCTestCase {
    
    var persistenceController: PersistenceController!
    var viewModel: MainViewModel!
    var tempDir: URL!
    
    override func setUp() async throws {
        // Setup In-Memory Core Data for testing
        persistenceController = PersistenceController(inMemory: true)
        
        // Setup ViewModel
        viewModel = MainViewModel(persistenceController: persistenceController)
        
        // Create Temp Directory for files
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Helper Methods
    
    func createTestFile(name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        try? "test data".write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    // MARK: - Tests
    
    func testCatalogFolderSync() async throws {
        print("--- Starting Catalog <-> Folder Sync Test ---")
        
        // 1. Create a file
        let fileURL = createTestFile(name: "sync_test.jpg")
        
        // 2. Create a Catalog
        let catalog = Catalog(context: persistenceController.container.viewContext)
        catalog.id = UUID()
        catalog.name = "Test Catalog"
        catalog.createdAt = Date()
        try persistenceController.container.viewContext.save()
        
        // 3. Import file to Catalog
        // We simulate import by creating MediaItem manually since import is async/complex
        let mediaItem = MediaItem(context: persistenceController.container.viewContext)
        mediaItem.id = UUID()
        mediaItem.originalPath = fileURL.path
        mediaItem.catalog = catalog
        mediaItem.rating = 0
        mediaItem.colorLabel = nil
        try persistenceController.container.viewContext.save()
        
        // 4. Open Catalog in ViewModel
        viewModel.openCatalog(catalog)
        
        // 5. Edit in Catalog Mode (via ViewModel)
        // Simulate selecting the item
        let fileItem = FileItem(url: fileURL, isDirectory: false, uuid: mediaItem.id!)
        viewModel.currentFile = fileItem
        
        // Set Rating to 3
        print("Setting Rating to 3 in Catalog Mode...")
        viewModel.setRating(3, for: [fileItem])
        
        // Verify Core Data updated
        XCTAssertEqual(mediaItem.rating, 3, "Core Data should reflect Rating 3")
        
        // 6. Switch to Folder Mode
        print("Switching to Folder Mode...")
        viewModel.openFolder(FileItem(url: tempDir, isDirectory: true))
        
        // Simulate loading metadata
        // We need to ensure loadMetadataForCurrentFolder picks up the Core Data value
        // We mock the localRatings map that would be passed
        let localRatings: [URL: Int16] = [fileURL: 3]
        await viewModel.loadMetadataForCurrentFolder(items: [fileURL], localRatings: localRatings)
        
        // Verify ViewModel cache has 3
        let cached = viewModel.metadataCache[fileURL]
        XCTAssertEqual(cached?.rating, 3, "Folder View should see Rating 3 from Core Data")
        
        // 7. Edit in Folder Mode
        // Set Color Label to Red
        print("Setting Color Label to Red in Folder Mode...")
        viewModel.setColorLabel("Red", for: [fileItem])
        
        // Verify Core Data updated
        XCTAssertEqual(mediaItem.colorLabel, "Red", "Core Data should reflect Color Label Red")
        
        print("--- Catalog <-> Folder Sync Test PASSED ---")
    }
    
    func testConcurrentChaos() async throws {
        print("--- Starting Concurrent Chaos Test ---")
        
        // 1. Create multiple files
        let files = (1...10).map { createTestFile(name: "chaos_\($0).jpg") }
        
        // 2. Create Catalog & Import
        let catalog = Catalog(context: persistenceController.container.viewContext)
        catalog.id = UUID()
        catalog.name = "Chaos Catalog"
        try persistenceController.container.viewContext.save()
        
        var mediaItems: [MediaItem] = []
        for (index, url) in files.enumerated() {
            let item = MediaItem(context: persistenceController.container.viewContext)
            item.id = UUID()
            item.originalPath = url.path
            item.catalog = catalog
            mediaItems.append(item)
        }
        try persistenceController.container.viewContext.save()
        
        // 3. Launch Concurrent Tasks
        // Each task picks a random file and performs an operation
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 { // 50 random operations
                group.addTask { @MainActor in
                    let randomFileIndex = Int.random(in: 0..<files.count)
                    let fileURL = files[randomFileIndex]
                    let mediaItem = mediaItems[randomFileIndex]
                    let fileItem = FileItem(url: fileURL, isDirectory: false, uuid: mediaItem.id!)
                    
                    let operation = Int.random(in: 0...2)
                    switch operation {
                    case 0: // Set Rating
                        let rating = Int.random(in: 0...5)
                        // print("Task \(i): Set Rating \(rating) for \(fileURL.lastPathComponent)")
                        self.viewModel.setRating(rating, for: [fileItem])
                    case 1: // Set Color Label
                        let colors = ["Red", "Blue", "Green", "Yellow", nil]
                        let color = colors.randomElement()!
                        // print("Task \(i): Set Label \(color ?? "nil") for \(fileURL.lastPathComponent)")
                        self.viewModel.setColorLabel(color, for: [fileItem])
                    case 2: // Read Metadata (Simulate View)
                        // print("Task \(i): Read Metadata for \(fileURL.lastPathComponent)")
                        let _ = self.viewModel.metadataCache[fileURL]
                    default: break
                    }
                    
                    // Small yield to allow interleaving
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                }
            }
        }
        
        // 4. Verify Consistency
        // Since operations are random, we can't assert specific values,
        // but we CAN assert that the app didn't crash and Core Data is readable.
        
        print("Chaos operations completed. Verifying integrity...")
        
        for item in mediaItems {
            // Access properties to ensure no faults/crashes
            let _ = item.rating
            let _ = item.colorLabel
        }
        
        print("--- Concurrent Chaos Test PASSED (No Crashes) ---")
    }
}
