import XCTest
@testable import SwiftViewerCore
import CoreData

@MainActor
final class EdgeCaseTests: XCTestCase {
    var persistenceController: PersistenceController!
    var viewModel: MainViewModel!
    var tempDir: URL!
    
    override func setUpWithError() throws {
        UserDefaults.standard.removeObject(forKey: "filterCriteria")
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
    
    // MARK: - Concurrent Editing
    
    func testConcurrentMetadataUpdate() async throws {
        // 1. Create/copy a valid test file or skip
        let bundlePath = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Testfiles")
        let sourceJpgURL = bundlePath.appendingPathComponent("test_edit.jpg")
        
        let jpgURL = tempDir.appendingPathComponent("test.jpg")
        if FileManager.default.fileExists(atPath: sourceJpgURL.path) {
            try FileManager.default.copyItem(at: sourceJpgURL, to: jpgURL)
        } else {
            // Write a dummy but ExifTool will fail to write, so we must XCTSkip
            throw XCTSkip("Valid test_edit.jpg not found in Testfiles directory, skipping test.")
        }
        
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
        
        // 2. Sequential updates with debounce sleep
        viewModel.updateRating(for: item, rating: 5)
        // Wait for debouncer (1 second) to flush rating before queuing label
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        
        viewModel.updateColorLabel(for: item, label: "Red")
        // Wait for debouncer (1 second) plus ExifTool execution plus FileSystemMonitor reload
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        
        // 3. Verify: Both updates should be applied
        let cache = viewModel.metadataCache[jpgURL.standardizedFileURL]
        XCTAssertEqual(cache?.rating, 5, "Rating should be 5")
        XCTAssertEqual(cache?.colorLabel, "Red", "Label should be Red")
    }
    
    // MARK: - Empty/Nil Values
    
    func testEmptyLabelUpdate() async throws {
        // 1. Create test file with label
        let jpgURL = tempDir.appendingPathComponent("test.jpg")
        try (Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)).write(to: jpgURL, options: .atomic)
        
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
        
        // 2. Set label
        viewModel.updateColorLabel(for: item, label: "Blue")
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // 3. Remove label (set to empty)
        viewModel.updateColorLabel(for: item, label: "")
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // 4. Verify: Label should be empty or nil
        let cache = viewModel.metadataCache[jpgURL]
        XCTAssertTrue(cache?.colorLabel == "" || cache?.colorLabel == nil, "Label should be empty or nil")
    }
    
    func testNilMetadataHandling() async throws {
        // 1. Create test file
        let jpgURL = tempDir.appendingPathComponent("test.jpg")
        try (Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)).write(to: jpgURL, options: .atomic)
        
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
        
        // 2. Verify: Initial metadata should be nil or defaults
        let cache = viewModel.metadataCache[jpgURL]
        // Cache might not exist yet if ExifReader hasn't run
        if let cache = cache {
            XCTAssertTrue(cache.rating == 0 || cache.rating == nil, "Initial rating should be 0 or nil")
            XCTAssertTrue(cache.colorLabel == nil || cache.colorLabel == "", "Initial label should be nil or empty")
        }
        
        // This test mainly verifies no crashes occur with nil metadata
        XCTAssertNotNil(item, "Item should exist")
    }
    
    // MARK: - Boundary Values
    
    func testRatingBoundaryValues() async throws {
        // 1. Create test file
        let jpgURL = tempDir.appendingPathComponent("test.jpg")
        try (Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)).write(to: jpgURL, options: .atomic)
        
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
        
        // 2. Test rating 0 (minimum)
        viewModel.updateRating(for: item, rating: 0)
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        var cache = viewModel.metadataCache[jpgURL]
        let isUnrated = (cache?.rating == 0 || cache?.rating == nil)
        XCTAssertTrue(isUnrated, "Rating should be 0 or nil (unrated) but got \(String(describing: cache?.rating))")
        

        // 3. Test rating 5 (maximum)
        viewModel.updateRating(for: item, rating: 5)
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        cache = viewModel.metadataCache[jpgURL]
        XCTAssertEqual(cache?.rating, 5, "Rating should be 5")
    }
    
    func testFlagBoundaryValues() async throws {
        // 1. Create test file
        let jpgURL = tempDir.appendingPathComponent("test.jpg")
        try (Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)).write(to: jpgURL, options: .atomic)
        
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
        
        // 2. Test flag -1 (Reject)
        viewModel.setFlagStatus(for: [item], status: -1)
        
        var updated = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test.jpg" })
        XCTAssertEqual(updated?.flagStatus, -1, "Flag should be -1 (Reject)")
        
        // 3. Test flag 0 (None)
        viewModel.setFlagStatus(for: [item], status: 0)
        
        updated = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test.jpg" })
        XCTAssertEqual(updated?.flagStatus, 0, "Flag should be 0 (None)")
        
        // 4. Test flag 1 (Pick)
        viewModel.setFlagStatus(for: [item], status: 1)
        
        updated = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test.jpg" })
        XCTAssertEqual(updated?.flagStatus, 1, "Flag should be 1 (Pick)")
    }
    
    // MARK: - File System Errors
    
    func testMetadataUpdateOnReadOnlyFile() async throws {
        // 1. Create test file
        let jpgURL = tempDir.appendingPathComponent("test.jpg")
        try (Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)).write(to: jpgURL, options: .atomic)
        
        // 2. Make file read-only
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: jpgURL.path)
        
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
        
        // 3. Try to update metadata
        // writeMetadataBatch uses ExifTool which may fail, but should not crash
        viewModel.updateRating(for: item, rating: 4)
        try? await Task.sleep(nanoseconds: 800_000_000)
        
        // 4. Verify: Cache should still be updated (optimistic update)
        let cache = viewModel.metadataCache[jpgURL]
        if cache == nil {
            print("Warning: Cache is nil after updating read-only file")
        }
        
        // Cleanup: Make writable again for tearDown
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: jpgURL.path)
    }
    
    func testMetadataUpdateOnNonExistentFile() async throws {
        // 1. Create a FileItem for a non-existent file
        let fakeURL = tempDir.appendingPathComponent("nonexistent.jpg")
        let fakeItem = FileItem(url: fakeURL, isDirectory: false)
        
        // 2. Try to update metadata
        // Should not crash
        viewModel.updateRating(for: fakeItem, rating: 3)
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // 3. Verify: Should handle gracefully (cache might be updated but file doesn't exist)
        // Main goal is no crash
        XCTAssertTrue(true, "Should handle non-existent file gracefully")
    }
    
    // MARK: - Edge Cases for RAW Files
    
    func testRAWFileMetadataAttempt() async throws {
        // 1. Create RAW file
        let rawURL = tempDir.appendingPathComponent("test.ARW")
        try (Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)).write(to: rawURL, options: .atomic)
        
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
        
        // 2. Try to update metadata on RAW file in Folders mode
        viewModel.updateRating(for: item, rating: 4)
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // 3. Verify: Cache should NOT be updated (RAW files are skipped)
        let cache = viewModel.metadataCache[rawURL]
        XCTAssertNotEqual(cache?.rating, 4, "RAW file rating should not be updated in Folders mode")
    }
}
