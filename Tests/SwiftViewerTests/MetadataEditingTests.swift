import XCTest
@testable import SwiftViewerCore
import CoreData

@MainActor
final class MetadataEditingTests: XCTestCase {
    var persistenceController: PersistenceController!
    var viewModel: MainViewModel!
    var tempDir: URL!
    
    override func setUpWithError() throws {
        persistenceController = PersistenceController(inMemory: true)
        viewModel = MainViewModel(persistenceController: persistenceController, inMemory: true)
        
        // Create temp directory
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testLabelDeletionRGB() async throws {
        // 1. Create dummy JPG
        let jpgURL = tempDir.appendingPathComponent("test.jpg")
        try "dummy".write(to: jpgURL, atomically: true, encoding: .utf8)
        
        // 2. Set Label to Red using batch (simulating selection)
        // We use batch because it was the one with the loop bug, and it's easier to test logic
        // But wait, batch also uses ExifTool.
        // If ExifTool fails, batch logs error and skips Finder Sync?
        // Let's check writeMetadataBatch code.
        /*
         do {
             try process.run()
             // ...
             // Sync Finder Labels
         } catch {
             Logger.shared.log("ExifTool Batch failed to run: \(error)")
         }
         */
        // Yes, if ExifTool fails, Finder Sync is skipped.
        // So this test depends on ExifTool working on "dummy" file.
        // ExifTool might complain "File format error" but exit with 0? Or non-zero?
        // If non-zero, process.run() doesn't throw, but we might check terminationStatus?
        // The code doesn't check terminationStatus before Finder Sync. It just runs Finder Sync after waitUntilExit.
        // So even if ExifTool fails (exit code 1), Finder Sync RUNS!
        // Unless process.run() throws (e.g. executable not found).
        
        // So if ExifTool is installed, this test should work even on dummy file (ExifTool will error, but Finder Sync will run).
        
        // Set Red
        await viewModel.writeMetadataBatch(to: [jpgURL], rating: nil, label: "Red")
        
        // Allow async task to complete (writeMetadataBatch is nonisolated but runs Process synchronously? No, Process.run is async-ish but we wait?
        // writeMetadataBatch calls process.waitUntilExit(), so it blocks the calling thread?
        // It is `nonisolated` and not `async`. So it blocks.
        
        // Verify Red Tag
        var values = try jpgURL.resourceValues(forKeys: [.tagNamesKey])
        XCTAssertTrue(values.tagNames?.contains("Red") == true, "Tag should be Red, got \(String(describing: values.tagNames))")
        
        // 3. Remove Label (Set to "")
        await viewModel.writeMetadataBatch(to: [jpgURL], rating: nil, label: "")
        
        // Verify Removed (empty or nil)
        values = try jpgURL.resourceValues(forKeys: [.tagNamesKey])
        XCTAssertTrue(values.tagNames == nil || values.tagNames?.isEmpty == true, "Tags should be removed, got \(String(describing: values.tagNames))")
    }
    
    func testRAWProtection() async throws {
        // 1. Create dummy RAW
        let rawURL = tempDir.appendingPathComponent("test.ARW")
        try "dummy".write(to: rawURL, atomically: true, encoding: .utf8)
        
        // 2. Try to set Label to Red
        await viewModel.writeMetadataBatch(to: [rawURL], rating: nil, label: "Red")
        
        // 3. Verify Tag is NOT set
        let values = try rawURL.resourceValues(forKeys: [.tagNamesKey])
        XCTAssertTrue(values.tagNames == nil || values.tagNames?.isEmpty == true, "Tags should NOT be set on RAW file, got \(String(describing: values.tagNames))")
    }
}
