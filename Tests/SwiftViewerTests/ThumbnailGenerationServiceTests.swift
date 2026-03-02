import XCTest
import CoreData
@testable import SwiftViewerCore

final class ThumbnailGenerationServiceTests: XCTestCase {
    
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            ThumbnailGenerationService.shared.cancelAll()
        }
    }
    
    override func tearDown() async throws {
        await MainActor.run {
            ThumbnailGenerationService.shared.cancelAll()
        }
        try await super.tearDown()
    }
    
    @MainActor
    func testProgressLogic() {
        let service = ThumbnailGenerationService.shared
        
        // Mock items
        let context = PersistenceController.shared.container.viewContext
        let item1 = MediaItem(context: context)
        let item2 = MediaItem(context: context)
        try? context.save()
        
        // Enqueue
        service.enqueue(items: [item1.objectID, item2.objectID])
        
        XCTAssertTrue(service.isGenerating)
        XCTAssertEqual(service.statusMessage, "Generating thumbnails...")
        XCTAssertEqual(service.remainingCount, 2)
        // Progress starts at 0
        XCTAssertEqual(service.progress, 0.0)
        
        // We can't easily wait for async task in unit test without expectation,
        // but we can verify initial state which was the bug (UI not showing).
    }
    
    @MainActor
    func testResumeLogic() {
        let service = ThumbnailGenerationService.shared
        
        // Simulate resume by enqueuing
        let context = PersistenceController.shared.container.viewContext
        let item1 = MediaItem(context: context)
        try? context.save()
        
        service.enqueue(items: [item1.objectID])
        
        XCTAssertTrue(service.isGenerating)
        XCTAssertEqual(service.statusMessage, "Generating thumbnails...")
    }
    
    @MainActor
    func testCancellation() async {
        let service = ThumbnailGenerationService.shared
        
        // Enqueue items
        let items = [createMediaItem().objectID, createMediaItem().objectID, createMediaItem().objectID]
        service.enqueue(items: items)
        
        // Cancel immediately
        service.cancelAll()
        
        // Wait for a short period to allow async tasks to process cancellation
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        XCTAssertFalse(service.isGenerating)
        XCTAssertEqual(service.statusMessage, "Cancelled")
        XCTAssertEqual(service.remainingCount, 0) // All items should be cleared
    }
    
    // Helper
    @MainActor
    private func createMediaItem() -> MediaItem {
        let context = PersistenceController.shared.container.viewContext
        let item = MediaItem(context: context)
        item.id = UUID()
        try? context.save()
        return item
    }
    
    @MainActor
    func testSuspendResumeLogic() async {
        let service = ThumbnailGenerationService.shared
        
        // Enqueue items
        let items = [createMediaItem().objectID, createMediaItem().objectID]
        service.enqueue(items: items)
        
        // Suspend immediately
        service.suspend()
        
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Resume
        service.resume()
        
        // Wait for resume to take effect
        for _ in 0..<10 {
            if service.isGenerating { break }
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
        }
        
        XCTAssertTrue(service.isGenerating)
    }
}
