import XCTest
import CoreData
@testable import SwiftViewerCore

final class ThumbnailGenerationServiceTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        ThumbnailGenerationService.shared.cancelAll()
    }
    
    override func tearDown() {
        ThumbnailGenerationService.shared.cancelAll()
        super.tearDown()
    }
    
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
    
    func testCancellation() {
        let service = ThumbnailGenerationService.shared
        let expectation = XCTestExpectation(description: "Cancellation should stop generation")
        
        // Enqueue items
        let items = [createMediaItem().objectID, createMediaItem().objectID, createMediaItem().objectID]
        service.enqueue(items: items)
        
        // Cancel immediately
        service.cancelAll()
        
        // Wait for a short period to allow async tasks to process cancellation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            XCTAssertFalse(service.isGenerating)
            XCTAssertEqual(service.statusMessage, "Cancelled")
            XCTAssertEqual(service.remainingCount, 0) // All items should be cleared
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // Helper
    private func createMediaItem() -> MediaItem {
        let context = PersistenceController.shared.container.viewContext
        let item = MediaItem(context: context)
        item.id = UUID()
        try? context.save()
        return item
    }
    
    func testSuspendResumeLogic() {
        let service = ThumbnailGenerationService.shared
        let expectation = XCTestExpectation(description: "Suspend should pause generation")
        
        // Enqueue items
        let items = [createMediaItem().objectID, createMediaItem().objectID]
        service.enqueue(items: items)
        
        // Suspend immediately
        service.suspend()
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            // Should be generating but paused loop
            // Actually, our implementation sets isProcessing=false when suspended in loop
            // But we can't easily check internal loop state.
            // We can check if progress stalls?
            
            // Resume
            service.resume()
            
            // Wait for resume to take effect
            for _ in 0..<10 {
                if service.isGenerating { break }
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
            }
            
            XCTAssertTrue(service.isGenerating)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}
