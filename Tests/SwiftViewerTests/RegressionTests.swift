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
        XCTAssertEqual(item1, item3, "Items with same ID should be equal (Identity equality)")
        XCTAssertEqual(item1, item4, "Items with same ID should be equal (Identity equality)")
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
        let dummyData = "dummy".data(using: .utf8)!
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
        let dummyData = "dummy".data(using: .utf8)!
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

