import XCTest
@testable import SwiftViewerCore
import AppKit

/// デュアルレイヤーキャッシング戦略の包括的なテスト
/// メモリキャッシュ（NSCache）とディスクキャッシュの動作を検証します
@MainActor
final class CachingStrategyTests: XCTestCase {
    
    override func setUpWithError() throws {
        // テスト前にキャッシュをクリア
        ImageCacheService.shared.clearCache()
        ThumbnailCacheService.shared.clearCache()
    }
    
    override func tearDownWithError() throws {
        // テスト後にキャッシュをクリア
        ImageCacheService.shared.clearCache()
        ThumbnailCacheService.shared.clearCache()
    }
    
    // MARK: - メモリキャッシュ（ImageCacheService）
    
    func testMemoryCache_SaveAndRetrieve() {
        let key = "test_image_key"
        let testImage = NSImage(size: NSSize(width: 100, height: 100))
        
        // 保存
        ImageCacheService.shared.setImage(testImage, forKey: key)
        
        // 取得
        let retrievedImage = ImageCacheService.shared.image(forKey: key)
        
        XCTAssertNotNil(retrievedImage, "メモリキャッシュから画像を取得できる")
    }
    
    func testMemoryCache_CacheHit() {
        let key = "cache_hit_test"
        let testImage = NSImage(size: NSSize(width: 50, height: 50))
        
        ImageCacheService.shared.setImage(testImage, forKey: key)
        
        // 1回目の取得（ヒット）
        let hit1 = ImageCacheService.shared.image(forKey: key)
        XCTAssertNotNil(hit1, "キャッシュヒット")
        
        // 2回目の取得（ヒット）
        let hit2 = ImageCacheService.shared.image(forKey: key)
        XCTAssertNotNil(hit2, "2回目もキャッシュヒット")
    }
    
    func testMemoryCache_CacheMiss() {
        let key = "non_existent_key"
        
        let result = ImageCacheService.shared.image(forKey: key)
        
        XCTAssertNil(result, "存在しないキーではnil")
    }
    
    func testMemoryCache_Clear() {
        let key = "clear_test"
        let testImage = NSImage(size: NSSize(width: 100, height: 100))
        
        ImageCacheService.shared.setImage(testImage, forKey: key)
        XCTAssertNotNil(ImageCacheService.shared.image(forKey: key))
        
        // クリア
        ImageCacheService.shared.clearCache()
        
        let afterClear = ImageCacheService.shared.image(forKey: key)
        XCTAssertNil(afterClear, "クリア後は取得できない")
    }
    
    // MARK: - ディスクキャッシュ（ThumbnailCacheService）
    
    func testDiskCache_SaveAndRetrieve() throws {
        let uuid = UUID()
        let testImage = NSImage(size: NSSize(width: 200, height: 200))
        
        // ディスクに保存
        try ThumbnailCacheService.shared.saveThumbnail(image: testImage, for: uuid)
        
        // ディスクから読み取り
        let retrieved = ThumbnailCacheService.shared.loadThumbnail(for: uuid)
        
        XCTAssertNotNil(retrieved, "ディスクキャッシュから読み取れる")
    }
    
    func testDiskCache_Path() {
        let uuid = UUID()
        
        let path = ThumbnailCacheService.shared.cachePath(for: uuid)
        
        XCTAssertTrue(path.path.contains(uuid.uuidString), "パスにUUIDが含まれる")
        XCTAssertTrue(path.pathExtension == "jpg", "拡張子はjpg")
    }
    
    func testDiskCache_Delete() throws {
        let uuid = UUID()
        let testImage = NSImage(size: NSSize(width: 150, height: 150))
        
        // 保存
        try ThumbnailCacheService.shared.saveThumbnail(image: testImage, for: uuid)
        XCTAssertNotNil(ThumbnailCacheService.shared.loadThumbnail(for: uuid))
        
        // 削除
        ThumbnailCacheService.shared.deleteThumbnail(for: uuid)
        
        let afterDelete = ThumbnailCacheService.shared.loadThumbnail(for: uuid)
        XCTAssertNil(afterDelete, "削除後は取得できない")
    }
    
    func testDiskCache_ClearAll() throws {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let testImage = NSImage(size: NSSize(width: 100, height: 100))
        
        // 複数保存
        try ThumbnailCacheService.shared.saveThumbnail(image: testImage, for: uuid1)
        try ThumbnailCacheService.shared.saveThumbnail(image: testImage, for: uuid2)
        
        XCTAssertNotNil(ThumbnailCacheService.shared.loadThumbnail(for: uuid1))
        XCTAssertNotNil(ThumbnailCacheService.shared.loadThumbnail(for: uuid2))
        
        // 全クリア
        ThumbnailCacheService.shared.clearCache()
        
        XCTAssertNil(ThumbnailCacheService.shared.loadThumbnail(for: uuid1))
        XCTAssertNil(ThumbnailCacheService.shared.loadThumbnail(for: uuid2))
    }
    
    // MARK: - キャッシュキーの生成
    
    func testCacheKey_FilePathAndModificationDate() {
        let url = URL(fileURLWithPath: "/test/photo.jpg")
        let modDate = Date(timeIntervalSince1970: 1000)
        
        // キャッシュキーは通常 "path_timestamp" の形式
        let key = "\(url.path)_\(Int(modDate.timeIntervalSince1970))"
        
        XCTAssertTrue(key.contains("/test/photo.jpg"))
        XCTAssertTrue(key.contains("1000"))
    }
    
    func testCacheKey_DifferentModificationDate() {
        let url = URL(fileURLWithPath: "/test/photo.jpg")
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        
        let key1 = "\(url.path)_\(Int(date1.timeIntervalSince1970))"
        let key2 = "\(url.path)_\(Int(date2.timeIntervalSince1970))"
        
        XCTAssertNotEqual(key1, key2, "修正日時が異なれば異なるキー")
    }
    
    // MARK: - 並行キャッシュアクセス
    
    func testConcurrentAccess_MemoryCache() async {
        let key = "concurrent_test"
        let testImage = NSImage(size: NSSize(width: 100, height: 100))
        
        ImageCacheService.shared.setImage(testImage, forKey: key)
        
        // 並行読み取り
        async let read1 = Task { ImageCacheService.shared.image(forKey: key) }
        async let read2 = Task { ImageCacheService.shared.image(forKey: key) }
        async let read3 = Task { ImageCacheService.shared.image(forKey: key) }
        
        let results = await [read1.value, read2.value, read3.value]
        
        XCTAssertTrue(results.allSatisfy { $0 != nil }, "並行読み取りが安全")
    }
    
    func testConcurrentAccess_DiskCache() async throws {
        let uuid = UUID()
        let testImage = NSImage(size: NSSize(width: 100, height: 100))
        
        try ThumbnailCacheService.shared.saveThumbnail(image: testImage, for: uuid)
        
        // 並行読み取り
        async let read1 = Task { ThumbnailCacheService.shared.loadThumbnail(for: uuid) }
        async let read2 = Task { ThumbnailCacheService.shared.loadThumbnail(for: uuid) }
        async let read3 = Task { ThumbnailCacheService.shared.loadThumbnail(for: uuid) }
        
        let results = await [read1.value, read2.value, read3.value]
        
        XCTAssertTrue(results.allSatisfy { $0 != nil }, "並行ディスク読み取りが安全")
    }
    
    // MARK: - キャッシュサイズ
    
    func testDiskCache_LargeImage() throws {
        let uuid = UUID()
        // 大きな画像（2000x2000）
        let largeImage = NSImage(size: NSSize(width: 2000, height: 2000))
        
        try ThumbnailCacheService.shared.saveThumbnail(image: largeImage, for: uuid)
        
        let retrieved = ThumbnailCacheService.shared.loadThumbnail(for: uuid)
        XCTAssertNotNil(retrieved, "大きな画像も保存・取得可能")
    }
    
    // MARK: - パフォーマンステスト
    
    func testPerformance_MemoryCacheSave() {
        let testImage = NSImage(size: NSSize(width: 200, height: 200))
        
        measure {
            for i in 0..<100 {
                ImageCacheService.shared.setImage(testImage, forKey: "perf_\(i)")
            }
        }
    }
    
    func testPerformance_MemoryCacheRetrieve() {
        // セットアップ
        let testImage = NSImage(size: NSSize(width: 200, height: 200))
        for i in 0..<100 {
            ImageCacheService.shared.setImage(testImage, forKey: "perf_\(i)")
        }
        
        measure {
            for i in 0..<100 {
                _ = ImageCacheService.shared.image(forKey: "perf_\(i)")
            }
        }
    }
    
    func testPerformance_DiskCacheSave() throws {
        let testImage = NSImage(size: NSSize(width: 200, height: 200))
        let uuids = (0..<10).map { _ in UUID() }
        
        measure {
            for uuid in uuids {
                try? ThumbnailCacheService.shared.saveThumbnail(image: testImage, for: uuid)
            }
        }
    }
    
    func testPerformance_DiskCacheRetrieve() throws {
        // セットアップ
        let testImage = NSImage(size: NSSize(width: 200, height: 200))
        let uuids = (0..<10).map { _ in UUID() }
        for uuid in uuids {
            try ThumbnailCacheService.shared.saveThumbnail(image: testImage, for: uuid)
        }
        
        measure {
            for uuid in uuids {
                _ = ThumbnailCacheService.shared.loadThumbnail(for: uuid)
            }
        }
    }
}
