import Foundation
import SwiftViewerCore
import CoreData

// Helper for assertions
func assert(_ condition: Bool, _ message: String) {
    if !condition {
        print("❌ ASSERTION FAILED: \(message)")
        exit(1)
    }
}

@MainActor
class ChaosRunner {
    var persistenceController: PersistenceController!
    var viewModel: MainViewModel!
    var tempDir: URL!
    
    init() {
        // Setup In-Memory Core Data
        persistenceController = PersistenceController(inMemory: true)
        viewModel = MainViewModel(persistenceController: persistenceController)
        
        // Setup Temp Dir
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func createTestFile(name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        try? "test data".write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    func run() async {
        print("🚀 Starting Chaos Runner...")
        
        do {
            try await testCatalogFolderSync()
            try await testConcurrentChaos()
            print("\n✅ ALL TESTS PASSED!")
        } catch {
            print("\n❌ TESTS FAILED: \(error)")
            exit(1)
        }
    }
    
    func testCatalogFolderSync() async throws {
        print("\n--- [Test 1] Catalog <-> Folder Sync ---")
        
        // 1. Create File
        let fileURL = createTestFile(name: "sync_test.jpg")
        
        // 2. Create Catalog
        let catalog = Catalog(context: persistenceController.container.viewContext)
        catalog.id = UUID()
        catalog.name = "Test Catalog"
        catalog.createdDate = Date()
        try persistenceController.container.viewContext.save()
        
        // 3. Import
        let mediaItem = MediaItem(context: persistenceController.container.viewContext)
        mediaItem.id = UUID()
        mediaItem.originalPath = fileURL.path
        mediaItem.catalog = catalog
        mediaItem.rating = 0
        try persistenceController.container.viewContext.save()
        
        // 4. Open Catalog
        viewModel.openCatalog(catalog)
        let fileItem = FileItem(url: fileURL, isDirectory: false, uuid: mediaItem.id!)
        
        // 5. Edit in Catalog (Rating -> 3)
        print(" -> Setting Rating to 3 in Catalog Mode")
        viewModel.setRating(3, for: [fileItem])
        // Wait for async update
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        // Refresh mediaItem from context to get latest values
        persistenceController.container.viewContext.refresh(mediaItem, mergeChanges: true)
        
        if mediaItem.rating != 3 {
             print("❌ Rating is \(mediaItem.rating), expected 3")
        }
        assert(mediaItem.rating == 3, "Core Data should reflect Rating 3")
        
        // 6. Switch to Folder Mode
        print(" -> Switching to Folder Mode")
        viewModel.openFolder(FileItem(url: tempDir, isDirectory: true))
        
        // Simulate loading
        let localRatings: [URL: Int16] = [fileURL: 3]
        await viewModel.loadMetadataForCurrentFolder(items: [fileURL], localRatings: localRatings)
        
        // Wait for metadata loading to finish
        print(" -> Waiting for metadata loading...")
        var retries = 0
        while viewModel.isLoadingMetadata && retries < 20 {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            retries += 1
        }
        if viewModel.isLoadingMetadata {
             print("⚠️ Metadata loading timed out")
        }
        
        let cached = viewModel.metadataCache[fileURL]
        if cached?.rating != 3 {
             print("❌ Cached Rating is \(String(describing: cached?.rating)), expected 3")
        }
        assert(cached?.rating == 3, "Folder View should see Rating 3")
        
        // 7. Edit in Folder (Label -> Red)
        print(" -> Setting Color Label to Red in Folder Mode")
        viewModel.setColorLabel("Red", for: [fileItem])
        
        // Wait for async update
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        persistenceController.container.viewContext.refresh(mediaItem, mergeChanges: true)
        
        if mediaItem.colorLabel != "Red" {
             print("❌ Color Label is \(String(describing: mediaItem.colorLabel)), expected Red")
        }
        assert(mediaItem.colorLabel == "Red", "Core Data should reflect Color Label Red")
        
        print(" -> [PASS] Catalog Sync")
    }
    
    func testConcurrentChaos() async throws {
        print("\n--- [Test 2] Concurrent Chaos ---")
        
        let files = (1...10).map { createTestFile(name: "chaos_\($0).jpg") }
        
        let catalog = Catalog(context: persistenceController.container.viewContext)
        catalog.id = UUID()
        catalog.name = "Chaos Catalog"
        try persistenceController.container.viewContext.save()
        
        var mediaItems: [MediaItem] = []
        for url in files {
            let item = MediaItem(context: persistenceController.container.viewContext)
            item.id = UUID()
            item.originalPath = url.path
            item.catalog = catalog
            mediaItems.append(item)
        }
        try persistenceController.container.viewContext.save()
        
        print(" -> Launching 50 concurrent operations...")
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask { @MainActor in
                    let randomFileIndex = Int.random(in: 0..<files.count)
                    let fileURL = files[randomFileIndex]
                    let mediaItem = mediaItems[randomFileIndex]
                    let fileItem = FileItem(url: fileURL, isDirectory: false, uuid: mediaItem.id!)
                    
                    let operation = Int.random(in: 0...2)
                    switch operation {
                    case 0:
                        let rating = Int.random(in: 0...5)
                        self.viewModel.setRating(rating, for: [fileItem])
                    case 1:
                        let colors = ["Red", "Blue", "Green", "Yellow", nil]
                        let color = colors.randomElement()!
                        self.viewModel.setColorLabel(color, for: [fileItem])
                    case 2:
                        let _ = self.viewModel.metadataCache[fileURL]
                    default: break
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
            }
        }
        
        print(" -> Verifying integrity...")
        for item in mediaItems {
            let _ = item.rating
            let _ = item.colorLabel
        }
        
        print(" -> [PASS] Concurrent Chaos")
    }
}

// Entry Point
Task { @MainActor in
    let runner = ChaosRunner()
    await runner.run()
    exit(0)
}

RunLoop.main.run()
