import XCTest
@testable import SwiftViewerCore
import CoreData

public final class RawMetadataTests: XCTestCase {
    var viewModel: MainViewModel!
    var tempDir: URL!
    
    @MainActor
    public override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Create temp directory
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Setup ViewModel with in-memory Core Data
        let persistence = PersistenceController(inMemory: true)
        viewModel = MainViewModel(persistenceController: persistence)
    }
    
    public override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDir)
        viewModel = nil
        try super.tearDownWithError()
    }
    
    @MainActor
    public func testRawMetadataImmutability() async throws {
        // Create dummy RAW file and JPG file
        let rawURL = tempDir.appendingPathComponent("test.ARW")
        let jpgURL = tempDir.appendingPathComponent("test.jpg")
        
        try "dummy raw content".write(to: rawURL, atomically: true, encoding: .utf8)
        try "dummy jpg content".write(to: jpgURL, atomically: true, encoding: .utf8)
        
        let rawItem = FileItem(url: rawURL, isDirectory: false)
        let jpgItem = FileItem(url: jpgURL, isDirectory: false)
        
        let items = [rawItem, jpgItem]
        
        // 1. Test Toggle Favorite
        // Initial state: both false
        XCTAssertFalse(rawItem.isFavorite ?? false)
        XCTAssertFalse(jpgItem.isFavorite ?? false)
        
        viewModel.toggleFavorite(for: items)
        
        // Wait for async update
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify: JPG should be favorite, RAW should NOT
        // Note: We need to check viewModel state or re-fetch, as FileItem struct copies might not update automatically 
        // unless we fetch from viewModel.allFiles or similar.
        // But toggleFavorite updates the passed items? No, it updates viewModel state.
        
        // Let's check viewModel.metadataCache first (optimistic update)
        let rawMeta = viewModel.metadataCache[rawURL.standardizedFileURL]
        let jpgMeta = viewModel.metadataCache[jpgURL.standardizedFileURL]
        
        XCTAssertNil(rawMeta?.isFavorite, "RAW file should not have favorite metadata in cache")
        XCTAssertTrue(jpgMeta?.isFavorite == true, "JPG file should have favorite metadata in cache")
        
        // 2. Test Update Rating
        viewModel.updateRating(for: items, rating: 5)
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let rawMeta2 = viewModel.metadataCache[rawURL.standardizedFileURL]
        let jpgMeta2 = viewModel.metadataCache[jpgURL.standardizedFileURL]
        
        XCTAssertNil(rawMeta2?.rating, "RAW file should not have rating in cache")
        XCTAssertEqual(jpgMeta2?.rating, 5, "JPG file should have rating 5 in cache")
        
        // 3. Test Update Color Label
        viewModel.updateColorLabel(for: items, label: "Red")
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let rawMeta3 = viewModel.metadataCache[rawURL.standardizedFileURL]
        let jpgMeta3 = viewModel.metadataCache[jpgURL.standardizedFileURL]
        
        XCTAssertNil(rawMeta3?.colorLabel, "RAW file should not have color label in cache")
        XCTAssertEqual(jpgMeta3?.colorLabel, "Red", "JPG file should have Red label in cache")
    }
}
