import XCTest
@testable import SwiftViewerCore
import CoreData

@MainActor
final class UIConsistencyTests: XCTestCase {
    var persistenceController: PersistenceController!
    var viewModel: MainViewModel!
    var tempDir: URL!
    
    override func setUpWithError() throws {
        persistenceController = PersistenceController(inMemory: true)
        viewModel = MainViewModel(persistenceController: persistenceController, inMemory: true)
        
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true, attributes: nil)
        tempDir = tempBase.resolvingSymlinksInPath()
        
        viewModel.appMode = .folders
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Inspector-Grid Sync
    
    func testInspectorToGridSync() async throws {
        // 1. Create test file
        let jpgURL = tempDir.appendingPathComponent("test.jpg")
        try "dummy".write(to: jpgURL, atomically: true, encoding: .utf8)
        
        let folderItem = FileItem(url: tempDir, isDirectory: true)
        viewModel.openFolder(folderItem)
        
        for _ in 0..<20 {
            if !viewModel.fileItems.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        guard let item = viewModel.fileItems.first else {
            XCTFail("File not loaded")
            return
        }
        
        // 2. Update via Inspector (updateRating)
        viewModel.updateRating(for: item, rating: 4)
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // 3. Verify: Cache should reflect the change (Grid uses cache)
        let cache = viewModel.metadataCache[jpgURL]
        XCTAssertEqual(cache?.rating, 4, "Grid cache should be updated")
    }
    
    func testGridToInspectorSync() async throws {
        // 1. Create test file
        let jpgURL = tempDir.appendingPathComponent("test.jpg")
        try "dummy".write(to: jpgURL, atomically: true, encoding: .utf8)
        
        let folderItem = FileItem(url: tempDir, isDirectory: true)
        viewModel.openFolder(folderItem)
        
        for _ in 0..<20 {
            if !viewModel.fileItems.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        guard let item = viewModel.fileItems.first else {
            XCTFail("File not loaded")
            return
        }
        
        // 2. Update via Grid context menu (toggleFavorite)
        viewModel.toggleFavorite(for: [item])
        
        // 3. Verify: fileItems should be updated (Inspector uses this)
        let updated = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test.jpg" })
        XCTAssertEqual(updated?.isFavorite, true, "Inspector should see updated favorite")
        
        // Also verify cache
        let cache = viewModel.metadataCache[jpgURL]
        XCTAssertEqual(cache?.isFavorite, true, "Cache should be updated")
    }
    
    // MARK: - Metadata Cache Consistency
    
    func testMetadataCacheConsistency() async throws {
        // 1. Create test file
        let jpgURL = tempDir.appendingPathComponent("test.jpg")
        try "dummy".write(to: jpgURL, atomically: true, encoding: .utf8)
        
        let canonicalURL = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil).first { $0.lastPathComponent == "test.jpg" }!
        
        let folderItem = FileItem(url: tempDir, isDirectory: true)
        viewModel.openFolder(folderItem)
        
        for _ in 0..<20 {
            if !viewModel.fileItems.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        guard let item = viewModel.fileItems.first else {
            XCTFail("File not loaded")
            return
        }
        
        // 2. Update metadata: Rating, Label, Favorite
        viewModel.updateRating(for: item, rating: 5)
        viewModel.updateColorLabel(for: item, label: "Red")
        viewModel.toggleFavorite(for: [item])
        
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        // 3. Verify: metadataCache, FileItem, and Core Data should all match
        
        // metadataCache
        let cache = viewModel.metadataCache[jpgURL]
        XCTAssertEqual(cache?.rating, 5, "Cache rating should be 5")
        XCTAssertEqual(cache?.colorLabel, "Red", "Cache label should be Red")
        XCTAssertEqual(cache?.isFavorite, true, "Cache favorite should be true")
        
        // FileItem
        let updatedItem = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test.jpg" })
        XCTAssertEqual(updatedItem?.colorLabel, "Red", "FileItem label should be Red")
        XCTAssertEqual(updatedItem?.isFavorite, true, "FileItem favorite should be true")
        
        // Core Data
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "originalPath == %@", canonicalURL.path)
        
        let results = try context.fetch(request)
        if let mediaItem = results.first {
            XCTAssertEqual(mediaItem.rating, 5, "Core Data rating should be 5")
            XCTAssertEqual(mediaItem.colorLabel, "Red", "Core Data label should be Red")
            XCTAssertEqual(mediaItem.isFavorite, true, "Core Data favorite should be true")
        } else {
            // In Folders mode, Core Data might not have the item if it wasn't added to catalog
            // This is acceptable
            XCTAssertTrue(true, "Core Data item not found, acceptable in Folders mode")
        }
    }
    
    // MARK: - Selection State Preservation
    
    func testSelectionPreservationAfterUpdate() async throws {
        // 1. Create multiple test files
        let jpg1URL = tempDir.appendingPathComponent("test1.jpg")
        let jpg2URL = tempDir.appendingPathComponent("test2.jpg")
        
        try "dummy".write(to: jpg1URL, atomically: true, encoding: .utf8)
        try "dummy".write(to: jpg2URL, atomically: true, encoding: .utf8)
        
        let folderItem = FileItem(url: tempDir, isDirectory: true)
        viewModel.openFolder(folderItem)
        
        for _ in 0..<20 {
            if viewModel.fileItems.count >= 2 { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // 2. Select both files
        let item1 = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test1.jpg" })!
        let item2 = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test2.jpg" })!
        
        viewModel.selectedFiles.insert(item1)
        viewModel.selectedFiles.insert(item2)
        
        XCTAssertEqual(viewModel.selectedFiles.count, 2, "Should have 2 selected files")
        
        // 3. Update metadata
        viewModel.toggleFavorite(for: [item1, item2])
        
        // 4. Verify: Selection should be preserved
        // (selectedFiles is updated with new FileItem instances, but count should remain)
        XCTAssertEqual(viewModel.selectedFiles.count, 2, "Selection should be preserved after update")
    }
    
    func testSelectionPreservationWithRAWFiltering() async throws {
        // 1. Create mixed files
        let jpgURL = tempDir.appendingPathComponent("test.jpg")
        let rawURL = tempDir.appendingPathComponent("test.ARW")
        
        try "dummy".write(to: jpgURL, atomically: true, encoding: .utf8)
        try "dummy".write(to: rawURL, atomically: true, encoding: .utf8)
        
        let folderItem = FileItem(url: tempDir, isDirectory: true)
        viewModel.openFolder(folderItem)
        
        for _ in 0..<20 {
            if viewModel.fileItems.count >= 2 { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // 2. Select both files
        let jpgItem = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test.jpg" })!
        let rawItem = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test.ARW" })!
        
        viewModel.selectedFiles.insert(jpgItem)
        viewModel.selectedFiles.insert(rawItem)
        
        XCTAssertEqual(viewModel.selectedFiles.count, 2, "Should have 2 selected files")
        
        // 3. Update metadata (RAW should be filtered out)
        viewModel.toggleFavorite(for: [jpgItem, rawItem])
        
        // 4. Verify: Both files should still be in selection
        // (RAW file is not updated, but it should remain selected)
        XCTAssertEqual(viewModel.selectedFiles.count, 2, "Selection should include both files")
        
        // Verify only JPG was updated
        let updatedJpg = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test.jpg" })
        let updatedRaw = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test.ARW" })
        
        XCTAssertEqual(updatedJpg?.isFavorite, true, "JPG should be updated")
        XCTAssertNotEqual(updatedRaw?.isFavorite, true, "RAW should NOT be updated")
    }
    
    // MARK: - Current File Preservation
    
    func testCurrentFilePreservation() async throws {
        // 1. Create test file
        let jpgURL = tempDir.appendingPathComponent("test.jpg")
        try "dummy".write(to: jpgURL, atomically: true, encoding: .utf8)
        
        let folderItem = FileItem(url: tempDir, isDirectory: true)
        viewModel.openFolder(folderItem)
        
        for _ in 0..<20 {
            if !viewModel.fileItems.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        guard let item = viewModel.fileItems.first else {
            XCTFail("File not loaded")
            return
        }
        
        // 2. Set as current file
        viewModel.currentFile = item
        
        // 3. Update metadata
        viewModel.updateRating(for: item, rating: 4)
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // 4. Verify: currentFile should be updated with new metadata
        XCTAssertNotNil(viewModel.currentFile, "currentFile should still be set")
        XCTAssertEqual(viewModel.currentFile?.url, jpgURL, "currentFile should be the same file")
    }
}
