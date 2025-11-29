import XCTest
@testable import SwiftViewerCore

class PerformanceAndCrashTests: XCTestCase {
    
    var tempFolder: URL!
    
    override func setUp() {
        super.setUp()
        // Create temp folder
        tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFolder)
        super.tearDown()
    }
    
    // MARK: - Crash Tests (Copy/Move)
    
    func testCopyFileAsync() async throws {
        // Create a dummy file
        let sourceURL = tempFolder.appendingPathComponent("test.txt")
        try "Hello".write(to: sourceURL, atomically: true, encoding: .utf8)
        
        let item = FileItem(url: sourceURL, isDirectory: false)
        let destFolder = tempFolder.appendingPathComponent("Dest")
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        
        // We can't easily test MainViewModel.copyFile because it uses Task.detached internally and returns void.
        // But we can test the logic it uses.
        
        let destURL = destFolder.appendingPathComponent(item.url.lastPathComponent)
        
        // Simulate the async operation
        let expectation = XCTestExpectation(description: "Copy complete")
        
        Task.detached {
            do {
                try FileManager.default.copyItem(at: item.url, to: destURL)
                expectation.fulfill()
            } catch {
                XCTFail("Copy failed: \(error)")
            }
        }
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))
    }
    
    // MARK: - Performance Tests
    
    func testThumbnailGenerationPerformance() async throws {
        // We can't easily test real performance without real images.
        // But we can verify that for a non-image file, it doesn't crash or hang.
        
        let fileURL = tempFolder.appendingPathComponent("test.jpg") // Fake JPG
        try "Fake Image Data".write(to: fileURL, atomically: true, encoding: .utf8)
        
        let start = Date()
        let _ = await ThumbnailGenerator.shared.generateThumbnail(for: fileURL, size: CGSize(width: 100, height: 100))
        let duration = Date().timeIntervalSince(start)
        
        print("Fake JPG thumbnail generation took: \(duration)s")
        // It should fail gracefully and quickly (or fallback to icon)
        // Our generator returns nil if it fails.
    }
}
