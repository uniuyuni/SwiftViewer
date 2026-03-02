import XCTest
@testable import SwiftViewerCore

final class RegressionTests: XCTestCase {
    
    func testFileItemEquality() {
        let url = URL(fileURLWithPath: "/tmp/test.jpg")
        let uuid = UUID()
        let date1 = Date()
        let date2 = date1.addingTimeInterval(100)
        
        let item1 = FileItem(url: url, isDirectory: false, uuid: uuid, fileCount: 10, modificationDate: date1)
        let item2 = FileItem(url: url, isDirectory: false, uuid: uuid, fileCount: 10, modificationDate: date1)
        let item3 = FileItem(url: url, isDirectory: false, uuid: uuid, fileCount: 11, modificationDate: date1)
        let item4 = FileItem(url: url, isDirectory: false, uuid: uuid, fileCount: 10, modificationDate: date2)
        
        XCTAssertEqual(item1, item2, "Identical items should be equal")
        XCTAssertEqual(item1.id, item3.id, "Items with same UUID should have same ID")
        XCTAssertNotEqual(item1, item3, "Items with different fileCount should not be equal")
        XCTAssertEqual(item1.id, item4.id, "Items with same UUID should have same ID")
        XCTAssertNotEqual(item1, item4, "Items with different modificationDate should not be equal")
    }
    
    func testFileSortService_DateSorting() {
        let url1 = URL(fileURLWithPath: "/tmp/1.jpg")
        let url2 = URL(fileURLWithPath: "/tmp/2.jpg")
        
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        
        let item1 = FileItem(url: url1, isDirectory: false, creationDate: date1, modificationDate: date1)
        let item2 = FileItem(url: url2, isDirectory: false, creationDate: date2, modificationDate: date2)
        
        // Basic sort by date ascending
        let sortedAsc = FileSortService.sortFiles([item2, item1], by: .date, ascending: true)
        XCTAssertEqual(sortedAsc.first?.url, url1)
        
        // Sort with Metadata Cache (EXIF override)
        var cache: [URL: ExifMetadata] = [:]
        var meta1 = ExifMetadata()
        meta1.dateTimeOriginal = date2 // 1.jpg actually taken later
        cache[url1.standardizedFileURL] = meta1
        
        var meta2 = ExifMetadata()
        meta2.dateTimeOriginal = date1 // 2.jpg actually taken earlier
        cache[url2.standardizedFileURL] = meta2
        
        let sortedExif = FileSortService.sortFiles([item1, item2], by: .date, ascending: true, metadataCache: cache)
        XCTAssertEqual(sortedExif.first?.url, url2, "Should sort by EXIF date")
    }
    
    func testCatalogDeletion_RemovesThumbnails() throws {
        // Setup Core Data
        let context = PersistenceController.shared.container.viewContext
        let repository = CatalogRepository(context: context)
        
        // Create Catalog
        let catalog = try repository.createCatalog(name: "Test Deletion Catalog")
        
        // Create MediaItem
        let item = MediaItem(context: context)
        item.id = UUID()
        item.catalog = catalog
        try context.save()
        
        // Create Dummy Thumbnail
        let thumbURL = ThumbnailCacheService.shared.cachePath(for: item.id!)
        let dummyData = Data(base64Encoded: "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", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)
        try? FileManager.default.createDirectory(at: thumbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try dummyData.write(to: thumbURL)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbURL.path), "Thumbnail should exist before deletion")
        
        // Delete Catalog
        try repository.deleteCatalog(catalog)
        
        // Verify Thumbnail is gone
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbURL.path), "Thumbnail should be deleted after catalog deletion")
    }
    
    func testFolderRemoval_RemovesThumbnails() throws {
        // Setup Core Data
        let context = PersistenceController.shared.container.viewContext
        let repository = CatalogRepository(context: context)
        
        // Create Catalog
        let catalog = try repository.createCatalog(name: "Test Folder Removal Catalog")
        
        // Create MediaItem in a specific folder
        let item = MediaItem(context: context)
        item.id = UUID()
        item.catalog = catalog
        item.originalPath = "/Users/test/Photos/Image.jpg"
        try context.save()
        
        // Create Dummy Thumbnail
        let thumbURL = ThumbnailCacheService.shared.cachePath(for: item.id!)
        let dummyData = Data(base64Encoded: "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", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)
        try? FileManager.default.createDirectory(at: thumbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try dummyData.write(to: thumbURL)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbURL.path), "Thumbnail should exist before deletion")
        
        // Simulate Folder Removal Logic (as in MainViewModel)
        let folderPath = "/Users/test/Photos"
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "originalPath BEGINSWITH %@", folderPath)
        
        let items = try context.fetch(request)
        for fetchedItem in items {
            if fetchedItem.catalog == catalog {
                if let uuid = fetchedItem.id {
                    ThumbnailCacheService.shared.deleteThumbnail(for: uuid)
                }
                context.delete(fetchedItem)
            }
        }
        try context.save()
        
        // Verify Thumbnail is gone
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbURL.path), "Thumbnail should be deleted after folder removal")
    }
}

