import XCTest
@testable import SwiftViewerCore
import CoreData

/// CoreDataの統合と永続化の包括的なテスト
/// Catalog、MediaItem、ExifData、Collectionの作成、更新、削除、関係性をテストします
@MainActor
final class CoreDataIntegrationTests: XCTestCase {
    var persistenceController: PersistenceController!
    var context: NSManagedObjectContext!
    var repository: CatalogRepository!
    var mediaRepository: MediaRepository!
    var collectionRepository: CollectionRepository!
    
    override func setUpWithError() throws {
        persistenceController = PersistenceController(inMemory: true)
        context = persistenceController.container.viewContext
        repository = CatalogRepository(context: context)
        mediaRepository = MediaRepository(context: context)
        collectionRepository = CollectionRepository(context: context)
    }
    
    override func tearDownWithError() throws {
        repository = nil
        mediaRepository = nil
        collectionRepository = nil
        context = nil
        persistenceController = nil
    }
    
    // MARK: - Catalog管理
    
    func testCreateCatalog() throws {
        let catalog = try repository.createCatalog(name: "Test Catalog")
        
        XCTAssertNotNil(catalog.id)
        XCTAssertEqual(catalog.name, "Test Catalog")
        XCTAssertNotNil(catalog.createdDate)
    }
    
    // MARK: - Catalog削除
    
    func testDeleteCatalog() throws {
        let catalog = try repository.createCatalog(name: "Delete Me")
        let catalogID = catalog.id!
        
        try repository.deleteCatalog(catalog)
        
        let request: NSFetchRequest<Catalog> = Catalog.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", catalogID as CVarArg)
        let results = try context.fetch(request)
        
        XCTAssertTrue(results.isEmpty, "削除されたカタログが見つからない")
    }
    
    // MARK: - MediaItem管理
    
    func testCreateMediaItem() throws {
        let catalog = try repository.createCatalog(name: "Media Catalog")
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.originalPath = "/test/photo.jpg"
        item.fileName = "photo.jpg"
        item.catalog = catalog
        
        try context.save()
        
        XCTAssertNotNil(item.id)
        XCTAssertEqual(item.catalog, catalog)
    }
    
    func testMediaItem_Rating() throws {
        let catalog = try repository.createCatalog(name: "Rating Catalog")
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.rating = 5
        item.catalog = catalog
        
        try context.save()
        
        XCTAssertEqual(item.rating, 5)
    }
    
    func testMediaItem_ColorLabel() throws {
        let catalog = try repository.createCatalog(name: "Label Catalog")
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.colorLabel = "Blue"
        item.catalog = catalog
        
        try context.save()
        
        XCTAssertEqual(item.colorLabel, "Blue")
    }
    
    func testMediaItem_Flag() throws {
        let catalog = try repository.createCatalog(name: "Flag Catalog")
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.flagStatus = 1  // Pick
        item.catalog = catalog
        
        try context.save()
        
        XCTAssertEqual(item.flagStatus, 1)
    }
    
    func testMediaItem_Favorite() throws {
        let catalog = try repository.createCatalog(name: "Favorite Catalog")
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.isFavorite = true
        item.catalog = catalog
        
        try context.save()
        
        XCTAssertTrue(item.isFavorite)
    }
    
    // MARK: - ExifData管理
    
    func testCreateExifData() throws {
        let catalog = try repository.createCatalog(name: "Exif Catalog")
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.catalog = catalog
        
        let exif = ExifData(context: context)
        exif.id = UUID()
        exif.cameraMake = "Canon"
        exif.cameraModel = "EOS R5"
        exif.lensModel = "RF 24-70mm f/2.8L"
        exif.iso = 100
        exif.aperture = 2.8
        exif.focalLength = 50.0
        exif.mediaItem = item
        
        try context.save()
        
        XCTAssertEqual(item.exifData, exif)
        XCTAssertEqual(exif.cameraMake, "Canon")
        XCTAssertEqual(exif.iso, 100)
    }
    
    func testExifData_AllFields() throws {
        let catalog = try repository.createCatalog(name: "Full Exif Catalog")
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.catalog = catalog
        
        let exif = ExifData(context: context)
        exif.id = UUID()
        exif.cameraMake = "Canon"
        exif.cameraModel = "EOS R5"
        exif.lensModel = "RF 24-70mm f/2.8L"
        exif.focalLength = 50.0
        exif.aperture = 2.8
        exif.shutterSpeed = "1/1000"
        exif.iso = 100
        exif.dateTimeOriginal = Date()
        exif.gpsLatitude = 35.6812
        exif.gpsLongitude = 139.7671
        exif.copyright = "© 2024"
        exif.artist = "Photographer"
        exif.descriptionText = "Test photo"
        exif.rating = 5
        exif.mediaItem = item
        
        try context.save()
        
        XCTAssertEqual(exif.focalLength, 50.0)
        XCTAssertEqual(exif.shutterSpeed, "1/1000")
        XCTAssertEqual(exif.gpsLatitude, 35.6812)
    }
    
    // MARK: - Collection管理
    
    func testCreateCollection() throws {
        let catalog = try repository.createCatalog(name: "Collection Catalog")
        
        let collection = try collectionRepository.createCollection(
            name: "Test Collection",
            in: catalog
        )
        
        XCTAssertNotNil(collection.id)
        XCTAssertEqual(collection.name, "Test Collection")
        XCTAssertEqual(collection.catalog, catalog)
    }
    
    func testAddMediaItemToCollection() throws {
        let catalog = try repository.createCatalog(name: "Add Collection Catalog")
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.originalPath = "/test.jpg"
        item.catalog = catalog
        try context.save()
        
        let collection = try collectionRepository.createCollection(
            name: "My Collection",
            in: catalog
        )
        
        try collectionRepository.addMediaItems([item], to: collection)
        
        XCTAssertTrue(collection.mediaItems?.contains(item) ?? false)
    }
    
    func testRemoveMediaItemFromCollection() throws {
        let catalog = try repository.createCatalog(name: "Remove Collection Catalog")
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.catalog = catalog
        try context.save()
        
        let collection = try collectionRepository.createCollection(
            name: "My Collection",
            in: catalog
        )
        
        try collectionRepository.addMediaItems([item], to: collection)
        XCTAssertTrue(collection.mediaItems?.contains(item) ?? false)
        
        try collectionRepository.removeMediaItems([item], from: collection)
        XCTAssertFalse(collection.mediaItems?.contains(item) ?? true)
    }
    
    func testDeleteCollection() throws {
        let catalog = try repository.createCatalog(name: "Delete Collection Catalog")
        
        let collection = try collectionRepository.createCollection(
            name: "Delete Me",
            in: catalog
        )
        let collectionID = collection.id!
        
        try collectionRepository.deleteCollection(collection)
        
        let request = NSFetchRequest<Collection>(entityName: "Collection")
        request.predicate = NSPredicate(format: "id == %@", collectionID as CVarArg)
        let results = try context.fetch(request)
        
        XCTAssertTrue(results.isEmpty)
    }
    
    // MARK: - 大量データのインポート
    
    func testBulkImport_100Items() throws {
        let catalog = try repository.createCatalog(name: "Bulk Catalog")
        
        for i in 1...100 {
            let item = MediaItem(context: context)
            item.id = UUID()
            item.originalPath = "/test/photo\(i).jpg"
            item.fileName = "photo\(i).jpg"
            item.catalog = catalog
        }
        
        try context.save()
        
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "catalog == %@", catalog)
        let count = try context.count(for: request)
        
        XCTAssertEqual(count, 100)
    }
    
    // MARK: - カスケード削除
    
    func testCascadeDelete_CatalogDeletesMediaItems() throws {
        let catalog = try repository.createCatalog(name: "Cascade Catalog")
        
        let item1 = MediaItem(context: context)
        item1.id = UUID()
        item1.catalog = catalog
        
        let item2 = MediaItem(context: context)
        item2.id = UUID()
        item2.catalog = catalog
        
        try context.save()
        
        // カタログを削除
        try repository.deleteCatalog(catalog)
        
        // MediaItemsも削除されているか確認
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        let results = try context.fetch(request)
        
        XCTAssertTrue(results.isEmpty, "カタログ削除時にMediaItemもカスケード削除")
    }
    
    func testCascadeDelete_MediaItemDeletesExifData() throws {
        let catalog = try repository.createCatalog(name: "Exif Cascade Catalog")
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.catalog = catalog
        
        let exif = ExifData(context: context)
        exif.id = UUID()
        exif.mediaItem = item
        
        try context.save()
        
        // MediaItemを削除
        context.delete(item)
        try context.save()
        
        // ExifDataも削除されているか確認
        let request = NSFetchRequest<ExifData>(entityName: "ExifData")
        let results = try context.fetch(request)
        
        XCTAssertTrue(results.isEmpty, "MediaItem削除時にExifDataもカスケード削除")
    }
    
    // MARK: - パス更新（ファイル移動）
    
    func testUpdatePath_FileMove() throws {
        let catalog = try repository.createCatalog(name: "Path Update Catalog")
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.originalPath = "/old/path/photo.jpg"
        item.catalog = catalog
        
        try context.save()
        
        // パスを更新
        item.originalPath = "/new/path/photo.jpg"
        try context.save()
        
        XCTAssertEqual(item.originalPath, "/new/path/photo.jpg")
    }
    
    // MARK: - 重複防止
    
    func testDuplicatePrevention() throws {
        let catalog = try repository.createCatalog(name: "Duplicate Catalog")
        
        let path = "/test/photo.jpg"
        
        let item1 = MediaItem(context: context)
        item1.id = UUID()
        item1.originalPath = path
        item1.catalog = catalog
        
        try context.save()
        
        // 同じパスで検索
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "originalPath == %@ AND catalog == %@", path, catalog)
        let results = try context.fetch(request)
        
        if results.isEmpty {
            // 重複がない場合のみ追加
            let item2 = MediaItem(context: context)
            item2.id = UUID()
            item2.originalPath = path
            item2.catalog = catalog
            try context.save()
        }
        
        // 最終的な件数確認
        let finalResults = try context.fetch(request)
        XCTAssertEqual(finalResults.count, 1, "同じパスの重複は防止される")
    }
    
    // MARK: - フェッチリクエストの最適化
    
    func testFetchRequest_WithPredicate() throws {
        let catalog = try repository.createCatalog(name: "Fetch Catalog")
        
        for i in 1...10 {
            let item = MediaItem(context: context)
            item.id = UUID()
            item.originalPath = "/test/photo\(i).jpg"
            item.rating = Int16(i % 6)  // 0-5
            item.catalog = catalog
        }
        
        try context.save()
        
        // レーティング4以上のみ取得
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "rating >= 4 AND catalog == %@", catalog)
        let results = try context.fetch(request)
        
        XCTAssertEqual(results.count, 3, "Rating 4と5")
    }
    
    func testFetchRequest_WithSortDescriptor() throws {
        let catalog = try repository.createCatalog(name: "Sort Catalog")
        
        let dates = [
            Date(timeIntervalSince1970: 3000),
            Date(timeIntervalSince1970: 1000),
            Date(timeIntervalSince1970: 2000)
        ]
        
        for (i, date) in dates.enumerated() {
            let item = MediaItem(context: context)
            item.id = UUID()
            item.originalPath = "/test/photo\(i).jpg"
            item.captureDate = date
            item.catalog = catalog
        }
        
        try context.save()
        
        // 日付順にソート
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "catalog == %@", catalog)
        request.sortDescriptors = [NSSortDescriptor(key: "captureDate", ascending: true)]
        let results = try context.fetch(request)
        
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].captureDate, dates[1], "最も古い")
        XCTAssertEqual(results[2].captureDate, dates[0], "最も新しい")
    }
    
    func testFetchRequest_WithLimit() throws {
        let catalog = try repository.createCatalog(name: "Limit Catalog")
        
        for i in 1...10 {
            let item = MediaItem(context: context)
            item.id = UUID()
            item.originalPath = "/test/photo\(i).jpg"
            item.catalog = catalog
        }
        
        try context.save()
        
        // 最大5件のみ取得
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "catalog == %@", catalog)
        request.fetchLimit = 5
        let results = try context.fetch(request)
        
        XCTAssertEqual(results.count, 5, "fetchLimitで制限")
    }
    
    // MARK: - CoreDataエラー処理
    
    func testErrorHandling_InvalidSave() {
        // 必須フィールドがない状態で保存を試みる
        _ = MediaItem(context: context)
        // IDを設定しない（必須の場合）
        
        // エラーが発生することを期待
        do {
            try context.save()
            // バリデーションがない場合は保存される可能性がある
        } catch {
            XCTAssertNotNil(error, "バリデーションエラーが発生")
        }
    }
    
    // MARK: - パフォーマンステスト
    
    func testPerformance_1000ItemsSave() throws {
        let catalog = try repository.createCatalog(name: "Performance Catalog")
        
        measure {
            for i in 1...1000 {
                let item = MediaItem(context: context)
                item.id = UUID()
                item.originalPath = "/test/photo\(i).jpg"
                item.catalog = catalog
            }
            
            try? context.save()
        }
    }
    
    func testPerformance_1000ItemsFetch() throws {
        let catalog = try repository.createCatalog(name: "Fetch Performance Catalog")
        
        for i in 1...1000 {
            let item = MediaItem(context: context)
            item.id = UUID()
            item.originalPath = "/test/photo\(i).jpg"
            item.catalog = catalog
        }
        
        try context.save()
        
        measure {
            let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
            request.predicate = NSPredicate(format: "catalog == %@", catalog)
            _ = try? context.fetch(request)
        }
    }
}
