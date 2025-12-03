import XCTest
@testable import SwiftViewerCore
import CoreData

final class CatalogCrashTests: XCTestCase {
    
    func testCreateExifDataWithNewFields() throws {
        let context = PersistenceController.shared.container.viewContext
        
        // Create Catalog
        let catalog = Catalog(context: context)
        catalog.id = UUID()
        catalog.name = "Crash Test Catalog"
        catalog.createdDate = Date()
        catalog.modifiedDate = Date()
        
        // Create MediaItem
        let item = MediaItem(context: context)
        item.id = UUID()
        item.catalog = catalog
        item.fileName = "test.jpg"
        item.originalPath = "/tmp/test.jpg"
        
        // Create ExifData
        let exifData = ExifData(context: context)
        exifData.id = UUID()
        exifData.mediaItem = item
        
        // Set old fields
        exifData.cameraMake = "Canon"
        
        // Set NEW fields
        exifData.software = "Lightroom"
        exifData.meteringMode = "Pattern"
        exifData.flash = "Off"
        exifData.whiteBalance = "Auto"
        exifData.exposureProgram = "Manual"
        exifData.exposureCompensation = -0.5
        
        item.exifData = exifData
        
        // Save
        try context.save()
        
        print("Successfully saved ExifData with new fields.")
    }
}
