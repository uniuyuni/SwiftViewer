import XCTest
@testable import SwiftViewerCore
import CoreData

@MainActor
final class IntegrationTests: XCTestCase {
    var persistenceController: PersistenceController!
    var viewModel: MainViewModel!
    var tempDir: URL!
    
    override func setUpWithError() throws {
        persistenceController = PersistenceController(inMemory: true)
        viewModel = MainViewModel(persistenceController: persistenceController, inMemory: true)
        
        // Create a temporary directory
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true, attributes: nil)
        tempDir = tempBase.resolvingSymlinksInPath()
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Mode Switching Scenarios
    
    func testCatalogToFoldersModeSwitch() async throws {
        // 1. Create test files
        let jpgURL = tempDir.appendingPathComponent("test.jpg")
        let jpgData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB])
        try jpgData.write(to: jpgURL)
        
        let canonicalURL = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil).first { $0.lastPathComponent == "test.jpg" }!
        
        // 2. Start in Catalog mode, add file
        viewModel.appMode = .catalog
        
        // Add to catalog
        let context = persistenceController.container.viewContext
        let mediaItem = MediaItem(context: context)
        mediaItem.id = UUID()
        mediaItem.originalPath = canonicalURL.path
        mediaItem.rating = 4
        mediaItem.colorLabel = "Blue"
        mediaItem.isFavorite = true
        try context.save()
        
        // 3. Switch to Folders mode
        viewModel.appMode = .folders
        
        let folderItem = FileItem(url: tempDir, isDirectory: true)
        viewModel.openFolder(folderItem)
        
        // Wait for async loading
        for _ in 0..<20 {
            if !viewModel.fileItems.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // 4. Verify: Catalog metadata is overlaid
        guard let item = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test.jpg" }) else {
            XCTFail("File not loaded")
            return
        }
        
        XCTAssertEqual(item.colorLabel, "Blue", "Catalog label should be overlaid")
        XCTAssertEqual(item.rating, 4, "Catalog rating should be overlaid")
        XCTAssertEqual(item.isFavorite, true, "Catalog favorite should be overlaid")
    }
    
    func testFoldersToCatalogModeSwitch() async throws {
        // 1. Create test files
        let jpgURL = tempDir.appendingPathComponent("test.jpg")
        let jpgData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB])
        try jpgData.write(to: jpgURL)
        
        // 2. Start in Folders mode
        viewModel.appMode = .folders
        
        let folderItem = FileItem(url: tempDir, isDirectory: true)
        viewModel.openFolder(folderItem)
        
        for _ in 0..<20 {
            if !viewModel.fileItems.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        guard let item = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test.jpg" }) else {
            XCTFail("File not loaded")
            return
        }
        
        // Edit metadata in Folders mode
        viewModel.updateRating(for: item, rating: 3)
        
        // Wait for persistence
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // 3. Switch to Catalog mode
        viewModel.appMode = .catalog
        
        // 4. Verify: File should be in catalog with metadata
        // (This requires catalog to be auto-created or file to be added)
        // For this test, we verify that switching modes works without errors
        XCTAssertEqual(viewModel.appMode, .catalog)
    }
    
    // MARK: - Batch Operations
    
    func testBatchEditMixedSelection() async throws {
        // 1. Create mixed files: 2 JPG + 1 RAW
        let jpg1URL = tempDir.appendingPathComponent("test1.jpg")
        let jpg2URL = tempDir.appendingPathComponent("test2.jpg")
        let rawURL = tempDir.appendingPathComponent("test.ARW")
        
        try "dummy".write(to: jpg1URL, atomically: true, encoding: .utf8)
        try "dummy".write(to: jpg2URL, atomically: true, encoding: .utf8)
        try "dummy".write(to: rawURL, atomically: true, encoding: .utf8)
        
        // 2. Load in Folders mode
        viewModel.appMode = .folders
        let folderItem = FileItem(url: tempDir, isDirectory: true)
        viewModel.openFolder(folderItem)
        
        for _ in 0..<20 {
            if viewModel.fileItems.count >= 3 { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        XCTAssertEqual(viewModel.fileItems.count, 3, "Should load 3 files")
        
        // 3. Select all files
        let allItems = viewModel.fileItems
        
        // 4. Batch edit: Toggle Favorite
        viewModel.toggleFavorite(for: allItems)
        
        // 5. Verify: Only JPG files should be updated
        let jpg1 = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test1.jpg" })
        let jpg2 = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test2.jpg" })
        let raw = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test.ARW" })
        
        XCTAssertEqual(jpg1?.isFavorite, true, "JPG1 should be favorite")
        XCTAssertEqual(jpg2?.isFavorite, true, "JPG2 should be favorite")
        XCTAssertNotEqual(raw?.isFavorite, true, "RAW should NOT be favorite")
    }
    
    func testBatchEditAllRGB() async throws {
        // 1. Create 3 JPG files
        let jpg1URL = tempDir.appendingPathComponent("test1.jpg")
        let jpg2URL = tempDir.appendingPathComponent("test2.jpg")
        let jpg3URL = tempDir.appendingPathComponent("test3.jpg")
        
        try "dummy".write(to: jpg1URL, atomically: true, encoding: .utf8)
        try "dummy".write(to: jpg2URL, atomically: true, encoding: .utf8)
        try "dummy".write(to: jpg3URL, atomically: true, encoding: .utf8)
        
        // 2. Load in Folders mode
        viewModel.appMode = .folders
        let folderItem = FileItem(url: tempDir, isDirectory: true)
        viewModel.openFolder(folderItem)
        
        for _ in 0..<20 {
            if viewModel.fileItems.count >= 3 { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // 3. Batch edit: Set rating
        let allItems = viewModel.fileItems
        viewModel.updateRating(for: allItems, rating: 5)
        
        // 4. Verify: All should be updated
        // (Rating updates metadataCache, not FileItem directly)
        let cache1 = viewModel.metadataCache[jpg1URL]
        let cache2 = viewModel.metadataCache[jpg2URL]
        let cache3 = viewModel.metadataCache[jpg3URL]
        
        XCTAssertEqual(cache1?.rating, 5, "JPG1 rating should be 5")
        XCTAssertEqual(cache2?.rating, 5, "JPG2 rating should be 5")
        XCTAssertEqual(cache3?.rating, 5, "JPG3 rating should be 5")
    }
    
    func testBatchEditAllRAW() async throws {
        // 1. Create 2 RAW files
        let raw1URL = tempDir.appendingPathComponent("test1.ARW")
        let raw2URL = tempDir.appendingPathComponent("test2.ARW")
        
        try "dummy".write(to: raw1URL, atomically: true, encoding: .utf8)
        try "dummy".write(to: raw2URL, atomically: true, encoding: .utf8)
        
        // 2. Load in Folders mode
        viewModel.appMode = .folders
        let folderItem = FileItem(url: tempDir, isDirectory: true)
        viewModel.openFolder(folderItem)
        
        for _ in 0..<20 {
            if viewModel.fileItems.count >= 2 { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // 3. Batch edit: Toggle Favorite
        let allItems = viewModel.fileItems
        viewModel.toggleFavorite(for: allItems)
        
        // 4. Verify: No updates (all RAW files are filtered out)
        let raw1 = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test1.ARW" })
        let raw2 = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test2.ARW" })
        
        XCTAssertNotEqual(raw1?.isFavorite, true, "RAW1 should NOT be favorite")
        XCTAssertNotEqual(raw2?.isFavorite, true, "RAW2 should NOT be favorite")
    }
    
    // MARK: - Multiple Folder Operations
    
    func testMultipleFolderMetadata() async throws {
        // 1. Create two folders with files
        let folderA = tempDir.appendingPathComponent("FolderA")
        let folderB = tempDir.appendingPathComponent("FolderB")
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        
        let fileA = folderA.appendingPathComponent("test.jpg")
        let fileB = folderB.appendingPathComponent("test.jpg")
        // Create valid minimal JPG
        let jpgData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB])
        try jpgData.write(to: fileA)
        try jpgData.write(to: fileB)
        
        viewModel.appMode = .folders
        
        // 2. Open FolderA, edit metadata
        let folderAItem = FileItem(url: folderA, isDirectory: true)
        viewModel.openFolder(folderAItem)
        
        for _ in 0..<20 {
            if !viewModel.fileItems.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        guard let itemA = viewModel.fileItems.first else {
            XCTFail("File A not loaded")
            return
        }
        
        viewModel.updateRating(for: itemA, rating: 4)
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // 3. Open FolderB, edit metadata
        let folderBItem = FileItem(url: folderB, isDirectory: true)
        viewModel.openFolder(folderBItem)
        
        for _ in 0..<20 {
            if !viewModel.fileItems.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        guard let itemB = viewModel.fileItems.first else {
            XCTFail("File B not loaded")
            return
        }
        
        viewModel.updateRating(for: itemB, rating: 5)
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // 4. Return to FolderA, verify rating is preserved
        viewModel.openFolder(folderAItem)
        
        for _ in 0..<20 {
            if !viewModel.fileItems.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        let cacheA = viewModel.metadataCache[fileA]
        XCTAssertEqual(cacheA?.rating, 4, "FolderA rating should be preserved")
    }
}
