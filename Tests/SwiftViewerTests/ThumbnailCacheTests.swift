import XCTest
@testable import SwiftViewerCore

final class ThumbnailCacheTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        ThumbnailCacheService.shared.clearCache()
    }
    
    override func tearDown() {
        ThumbnailCacheService.shared.clearCache()
        super.tearDown()
    }
    
    func testMemoryCache() {
        let id = UUID()
        let image = NSImage(size: NSSize(width: 100, height: 100))
        
        // Save
        ThumbnailCacheService.shared.saveThumbnail(image: image, for: id)
        
        // Load from Memory (should be immediate)
        let cached = ThumbnailCacheService.shared.loadFromMemory(for: id)
        XCTAssertNotNil(cached, "Should be in memory cache")
        
        // Load from Disk (should also work)
        let disk = ThumbnailCacheService.shared.loadThumbnail(for: id)
        XCTAssertNotNil(disk, "Should be on disk")
    }
    
    func testDeletion() {
        let id = UUID()
        let image = NSImage(size: NSSize(width: 100, height: 100))
        ThumbnailCacheService.shared.saveThumbnail(image: image, for: id)
        
        ThumbnailCacheService.shared.deleteThumbnail(for: id)
        
        XCTAssertNil(ThumbnailCacheService.shared.loadFromMemory(for: id))
        XCTAssertFalse(ThumbnailCacheService.shared.hasThumbnail(for: id))
    }
}
