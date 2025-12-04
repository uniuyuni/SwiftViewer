import XCTest
@testable import SwiftViewerCore
import CoreData

@MainActor
final class MetadataEditingNonCatalogTests: XCTestCase {
    var persistenceController: PersistenceController!
    var viewModel: MainViewModel!
    var tempDir: URL!
    
    override func setUpWithError() throws {
        persistenceController = PersistenceController(inMemory: true)
        viewModel = MainViewModel(persistenceController: persistenceController, inMemory: true)
        
        // Create temp directory
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Set mode to Folders (Non-Catalog)
        viewModel.appMode = .folders
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testToggleFavoriteRGB_NonCatalog() async throws {
        // 1. Create dummy JPG
        let jpgURL = tempDir.appendingPathComponent("test_fav.jpg")
        try "dummy".write(to: jpgURL, atomically: true, encoding: .utf8)
        let item = FileItem(url: jpgURL, isDirectory: false)
        
        // 2. Toggle Favorite (ON)
        viewModel.toggleFavorite(for: [item])
        
        // 3. Verify Metadata Update (ExifTool args)
        // Since we can't easily spy on Process, we rely on the fact that writeMetadataBatch is called.
        // And if writeMetadataBatch is called, it logs.
        // But better, we can check if the item's state in ViewModel is updated?
        // In non-catalog mode, toggleFavorite updates `fileItems` and `allFiles`.
        // But `fileItems` might be empty if we didn't load folder.
        // Let's manually populate fileItems to simulate being in a folder.
        viewModel.fileItems = [item]
        viewModel.toggleFavorite(for: [item])
        
        // Verify ViewModel state
        XCTAssertTrue(viewModel.fileItems.first?.isFavorite == true, "ViewModel item should be favorite")
        
        // Verify Metadata Cache (invalidated?)
        // We can't easily check cache invalidation directly without mocking ExifReader.
        // But we can check if `writeMetadataBatch` logic for RAW protection works here too.
    }
    
    func testToggleFavoriteRAW_NonCatalog() async throws {
        // 1. Create dummy RAW
        let rawURL = tempDir.appendingPathComponent("test_fav.ARW")
        try "dummy".write(to: rawURL, atomically: true, encoding: .utf8)
        let item = FileItem(url: rawURL, isDirectory: false)
        viewModel.fileItems = [item]
        
        // 2. Toggle Favorite (ON)
        viewModel.toggleFavorite(for: [item])
        
        // 3. Verify ViewModel state (it updates in memory!)
        // Wait, if we are in non-catalog mode, do we allow updating RAW in memory?
        // The user said "RAW files is OK as is" (meaning Read-Only?).
        // If we update in memory but don't write to file, it's temporary.
        // But `writeMetadataBatch` skips RAW.
        // So file is NOT touched.
        // But UI might show Favorite ON until refresh?
        // That seems acceptable or maybe we should block it in UI too?
        // "RAW画像は今のままでOK" -> "RAW images are OK as they are now".
        // Previously, they were read-only.
        // So we should probably NOT update them even in memory if we can't write?
        // But `toggleFavorite` updates memory first.
        // If `writeMetadataBatch` skips, then we have desync.
        // But since it's non-catalog, the "source of truth" is the file.
        // If file isn't updated, next reload will show it as off.
        // This seems fine.
        
        XCTAssertFalse(viewModel.fileItems.first?.isFavorite == true, "ViewModel should NOT update RAW in memory in Folders mode")
        
        // But crucial part is that `writeMetadataBatch` skips it.
        // We verified that in `MetadataEditingTests`.
    }
    
    func testSetFlagRGB_NonCatalog() async throws {
        // 1. Create dummy JPG
        let jpgURL = tempDir.appendingPathComponent("test_flag.jpg")
        try "dummy".write(to: jpgURL, atomically: true, encoding: .utf8)
        let item = FileItem(url: jpgURL, isDirectory: false)
        viewModel.fileItems = [item]
        
        // 2. Set Flag (Pick = 1)
        viewModel.setFlagStatus(for: [item], status: 1)
        
        // 3. Verify ViewModel state
        XCTAssertEqual(viewModel.fileItems.first?.flagStatus, 1, "ViewModel item should be flagged Pick")
    }
}
