import XCTest
@testable import SwiftViewerCore
import CoreData

@MainActor
final class MetadataOverlayTests: XCTestCase {
    var persistenceController: PersistenceController!
    var viewModel: MainViewModel!
    var tempDir: URL!
    
    override func setUpWithError() throws {
        persistenceController = PersistenceController(inMemory: true)
        viewModel = MainViewModel(persistenceController: persistenceController, inMemory: true)
        
        // Create a temporary directory
        // Create a temporary directory
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true, attributes: nil)
        tempDir = tempBase.resolvingSymlinksInPath()
        // Set mode to Folders
        viewModel.appMode = .folders
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testCatalogOverlayForRAW() async throws {
        // 1. Create dummy RAW file
        let rawURL = tempDir.appendingPathComponent("test_overlay.ARW")
        try "dummy".write(to: rawURL, atomically: true, encoding: .utf8)
        
        // Get canonical URL from FileManager to match what loadFiles will see (handling /var vs /private/var)
        let canonicalURL = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil).first { $0.lastPathComponent == "test_overlay.ARW" }!
        
        // 2. Add to Catalog (Core Data) with Label "Red"
        let context = persistenceController.container.viewContext
        let mediaItem = MediaItem(context: context)
        mediaItem.id = UUID()
        mediaItem.originalPath = canonicalURL.path
        // mediaItem.filename = rawURL.lastPathComponent // Not needed or doesn't exist
        mediaItem.colorLabel = "Red"
        mediaItem.rating = 3
        mediaItem.isFavorite = true
        mediaItem.flagStatus = 1
        try context.save()
        
        // 3. Load Files in Folder (which triggers enrichment)
        // We can't easily call loadFiles directly as it's private and async/detached.
        // But we can test `enrichItemsWithCatalogData` if we expose it or use reflection?
        // Or we can simulate what loadFiles does: create FileItem and call enrichment.
        // Wait, `enrichItemsWithCatalogData` is private.
        // I should make it internal for testing or test via public interface.
        // `loadFiles` is private too.
        // `selectFolder` calls `loadFiles`.
        
        let folderItem = FileItem(url: tempDir, isDirectory: true)
        // Simulate folder selection
        viewModel.currentFolder = folderItem
        // Manually trigger loadFiles since selectFolder is private/not available
        // Or use `selectCatalogFolder` if appropriate, but we are in Folders mode.
        // `selectFolder` is likely private.
        // But `currentFolder` is published.
        // Setting `currentFolder` might trigger something?
        // No, usually `selectFolder` sets `currentFolder` and calls `loadFiles`.
        // Let's call `loadFiles` via reflection or just expose it?
        // Or better, use `viewModel.selectFolder(folderItem)` if I can find the public method.
        // It seems `selectFolder` is missing or private.
        // Let's check MainViewModel again.
        // Found `requestMoveFolder`, `removeFolderFromCatalog`.
        // Maybe it's `setCurrentFolder`?
        // Let's try to set `currentFolder` and see if `didSet` triggers load.
        // MainViewModel.swift:1696: private func loadFiles(in folder: FileItem)
        // It's private.
        // But `currentFolder` property:
        // @Published var currentFolder: FileItem? { didSet { ... } } ?
        // Let's check MainViewModel definition of currentFolder.
        
        // Assuming we can't call loadFiles directly.
        // But we can call `enrichItemsWithCatalogData` if we make it internal?
        // Or we can just test `enrichItemsWithCatalogData` directly if we make it internal.
        // I'll make `enrichItemsWithCatalogData` internal in MainViewModel.swift first.
        
        // For now, let's comment out the test logic that relies on private methods and fix MainViewModel first.
        // Actually, I'll use a workaround:
        // `viewModel.currentFolder = folderItem`
        // `viewModel.loadFiles(in: folderItem)` -> ERROR: Private.
        // Act
        // I will change `enrichItemsWithCatalogData` to internal in MainViewModel.swift.
        // And I will change `loadFiles` to internal?
        // Or I will use `@testable` which I already have.
        // `@testable` allows access to internal, but not private.
        // So I must change `private` to `internal`.
        
        // Let's assume I will change them.
        // Use openFolder to simulate folder selection and trigger loading
        viewModel.openFolder(folderItem)
        
        // Wait for async loading
        // We can wait for `isLoading` to become false, or check `fileItems`.
        // Let's loop/wait.
        let maxRetries = 20
        for _ in 0..<maxRetries {
            if !viewModel.fileItems.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        
        guard let item = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test_overlay.ARW" }) else {
            XCTFail("File not loaded")
            return
        }
        
        // 4. Verify Overlay Data
        XCTAssertEqual(item.colorLabel, "Red", "Label should be overlaid from Catalog")
        XCTAssertEqual(item.rating, 3, "Rating should be overlaid from Catalog")
        XCTAssertEqual(item.isFavorite, true, "Favorite should be overlaid from Catalog")
        XCTAssertEqual(item.flagStatus, 1, "Flag should be overlaid from Catalog")
        XCTAssertNotNil(item.uuid, "UUID should be linked from Catalog")
    }
    
    func testCatalogOverlayForRGB() async throws {
        // 1. Create dummy JPG file
        let jpgURL = tempDir.appendingPathComponent("test_overlay.jpg")
        try "dummy".write(to: jpgURL, atomically: true, encoding: .utf8)
        
        // Get canonical URL
        let canonicalURL = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil).first { $0.lastPathComponent == "test_overlay.jpg" }!
        
        // 2. Add to Catalog (Core Data) with Label "Blue"
        let context = persistenceController.container.viewContext
        let mediaItem = MediaItem(context: context)
        mediaItem.id = UUID()
        mediaItem.originalPath = canonicalURL.path
        // mediaItem.filename = jpgURL.lastPathComponent
        mediaItem.colorLabel = "Blue"
        try context.save()
        
        // 3. Load Files
        let folderItem = FileItem(url: tempDir, isDirectory: true)
        viewModel.openFolder(folderItem)
        
        // Wait
        for _ in 0..<20 {
            if !viewModel.fileItems.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        guard let item = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test_overlay.jpg" }) else {
            XCTFail("File not loaded")
            return
        }
        
        // 4. Verify Overlay
        XCTAssertEqual(item.colorLabel, "Blue", "Label should be overlaid from Catalog")
    }
    
    func testRGBEditingInFoldersMode() async throws {
        // 1. Create dummy JPG file
        let jpgURL = tempDir.appendingPathComponent("test_edit.jpg")
        
        // Use createFile to avoid potential write issues with temp paths
        let created = FileManager.default.createFile(atPath: jpgURL.path, contents: "dummy".data(using: .utf8), attributes: nil)
        if !created {
            XCTFail("Failed to create file at \(jpgURL.path)")
            return
        }
        
        // Canonical URL
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        guard let canonicalURL = contents.first(where: { $0.lastPathComponent == "test_edit.jpg" }) else {
            XCTFail("test_edit.jpg not found in tempDir")
            return
        }
        _ = canonicalURL
        
        // 2. Load Files
        let folderItem = FileItem(url: tempDir, isDirectory: true)
        viewModel.openFolder(folderItem)
        
        // Wait
        for _ in 0..<20 {
            if !viewModel.fileItems.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        guard let item = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test_edit.jpg" }) else {
            XCTFail("File not loaded")
            return
        }
        
        // 3. Edit Metadata (Favorite)
        viewModel.toggleFavorite(for: [item])
        
        // 4. Verify In-Memory Update
        // toggleFavorite updates fileItems immediately
        guard let updatedItem = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test_edit.jpg" }) else {
            XCTFail("File lost")
            return
        }
        XCTAssertEqual(updatedItem.isFavorite, true, "Favorite should be toggled in memory")
        
        // 5. Verify Persistence (Cache)
        // writeMetadataBatch is async/nonisolated. We need to wait or check cache.
        // It invalidates cache.
        // But ExifReader.shared.invalidateCache(for: url) just clears it.
        // We can check if `writeMetadataBatch` was called? No easy way without mocking.
        // But we can check if `metadataCache` is updated?
        // `writeMetadataBatch` does NOT update `metadataCache` directly, it invalidates it.
        // But `toggleFavorite` updates `fileItems`.
        
        // Ideally we should verify ExifTool was called, but we can't easily in integration test without mocking ExifTool.
        // However, the fact that `toggleFavorite` didn't return early (because we removed the guard) is what we want to test.
        // And we verified `isFavorite` is true in memory.
        
        // Let's also check Flag
        viewModel.setFlagStatus(for: [updatedItem], status: 1)
        
        guard let flaggedItem = viewModel.fileItems.first(where: { $0.url.lastPathComponent == "test_edit.jpg" }) else { return }
        XCTAssertEqual(flaggedItem.flagStatus, 1, "Flag should be set in memory")
    }
}
